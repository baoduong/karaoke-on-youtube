import Testing
import Foundation
import SwiftData
@testable import Karaoke

// MARK: - StoreReconcilerTests (T042)

/// Tests for StoreReconciler's enforcement of data-model.md's cross-entity
/// invariants (T025).
///
/// Constitution Principle IV: test what can silently rot. The reconciler runs
/// at launch and its failures are invisible — a Song that should have been
/// deleted stays, or a SavedSong record points to a missing file. These tests
/// verify the logic that prevents those silent corruptions.
///
/// All tests use an in-memory ModelContainer so they never touch the real store
/// or the real media directory.
@Suite("StoreReconciler")
@MainActor
struct StoreReconcilerTests {

    // MARK: - Helpers

    /// Creates an in-memory ModelContainer and a temporary media directory.
    private static func makeTestEnvironment() throws -> (ModelContext, URL) {
        let schema = Schema([
            Song.self,
            SavedSong.self,
            Favourite.self,
            QueueEntry.self,
            PerformanceSettings.self,
            LyricsTrack.self,
            LyricsLine.self,
            LyricsWord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let mediaDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReconcilerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        return (context, mediaDir)
    }

    /// Inserts a minimal valid Song into the context.
    private static func insertSong(id: String, context: ModelContext) -> Song {
        let song = Song(
            id: id,
            title: "Alpha Song",
            channelName: "Bravo Channel",
            durationSeconds: 180
        )
        context.insert(song)
        return song
    }

    // MARK: - Invariant 1: Orphaned references are repaired

    @Suite("Invariant 1 — orphaned references")
    struct OrphanedReferenceTests {

        @Test("orphaned QueueEntry is deleted")
        @MainActor
        func orphanedQueueEntryDeleted() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            // Insert a QueueEntry with no corresponding Song.
            let entry = QueueEntry(songID: "orphanID1", position: 0)
            context.insert(entry)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<QueueEntry>())
            #expect(remaining.isEmpty)
        }

        @Test("orphaned Favourite is deleted")
        @MainActor
        func orphanedFavouriteDeleted() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let fav = Favourite(songID: "orphanID2")
            context.insert(fav)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<Favourite>())
            #expect(remaining.isEmpty)
        }

        @Test("orphaned SavedSong is deleted")
        @MainActor
        func orphanedSavedSongDeleted() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let saved = SavedSong(
                songID: "orphanID3",
                fileRelativePath: "orphan.m4a",
                container: .m4a,
                codec: .aac,
                state: .complete
            )
            context.insert(saved)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<SavedSong>())
            #expect(remaining.isEmpty)
        }

        @Test("orphaned LyricsTrack is deleted")
        @MainActor
        func orphanedLyricsTrackDeleted() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let track = LyricsTrack(songID: "orphanID4", source: .lrclib, hasWordTiming: false)
            context.insert(track)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<LyricsTrack>())
            #expect(remaining.isEmpty)
        }

        @Test("valid references are preserved")
        @MainActor
        func validReferencesPreserved() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "validSong1", context: context)
            let fav = Favourite(songID: song.id)
            context.insert(fav)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remainingFavs = try context.fetch(FetchDescriptor<Favourite>())
            #expect(remainingFavs.count == 1)
            let remainingSongs = try context.fetch(FetchDescriptor<Song>())
            #expect(remainingSongs.count == 1)
        }
    }

    // MARK: - Invariant 2: Unreferenced Songs are removed

    @Suite("Invariant 2 — unreferenced Song cleanup")
    struct UnreferencedSongTests {

        @Test("Song with no references is deleted")
        @MainActor
        func unreferencedSongDeleted() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            _ = insertSong(id: "unreferencedSong1", context: context)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<Song>())
            #expect(remaining.isEmpty)
        }

        @Test("Song referenced by Favourite is retained")
        @MainActor
        func songReferencedByFavouriteRetained() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "favSong1", context: context)
            context.insert(Favourite(songID: song.id))

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<Song>())
            #expect(remaining.count == 1)
        }

        @Test("Song referenced by QueueEntry is retained")
        @MainActor
        func songReferencedByQueueEntryRetained() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "queueSong1", context: context)
            context.insert(QueueEntry(songID: song.id, position: 0))

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<Song>())
            #expect(remaining.count == 1)
        }

        @Test("Song referenced by SavedSong is retained")
        @MainActor
        func songReferencedBySavedSongRetained() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "savedSong1", context: context)
            context.insert(SavedSong(
                songID: song.id,
                fileRelativePath: "saved.m4a",
                container: .m4a,
                codec: .aac,
                state: .complete
            ))

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<Song>())
            #expect(remaining.count == 1)
        }

        @Test("LyricsTrack is deleted when its Song is removed")
        @MainActor
        func lyricsTrackDeletedWithUnreferencedSong() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "unreferencedWithLyrics1", context: context)
            context.insert(LyricsTrack(songID: song.id, source: .lrclib, hasWordTiming: false))

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remainingSongs = try context.fetch(FetchDescriptor<Song>())
            #expect(remainingSongs.isEmpty)
            let remainingTracks = try context.fetch(FetchDescriptor<LyricsTrack>())
            #expect(remainingTracks.isEmpty)
        }
    }

    // MARK: - Invariant 6: SavedSong file system reconciliation

    @Suite("Invariant 6 — SavedSong file reconciliation")
    struct SavedSongFileReconciliationTests {

        @Test("complete SavedSong with missing file is moved to failed")
        @MainActor
        func completeSavedSongMissingFileMoved() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "missingSong1", context: context)
            let saved = SavedSong(
                songID: song.id,
                fileRelativePath: "missing.m4a",
                container: .m4a,
                codec: .aac,
                byteSize: 1024,
                state: .complete
            )
            context.insert(saved)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<SavedSong>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .failed)
            #expect(remaining[0].lastError != nil)
        }

        @Test("complete SavedSong with existing file is left intact")
        @MainActor
        func completeSavedSongWithFileLeftIntact() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            // Create the actual file.
            let fileName = "present.m4a"
            let fileURL = mediaDir.appendingPathComponent(fileName)
            try Data("alpha bravo".utf8).write(to: fileURL)

            let song = insertSong(id: "presentSong1", context: context)
            let saved = SavedSong(
                songID: song.id,
                fileRelativePath: fileName,
                container: .m4a,
                codec: .aac,
                byteSize: Int64("alpha bravo".utf8.count),
                state: .complete
            )
            context.insert(saved)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<SavedSong>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .complete)
        }

        @Test("orphaned file with no SavedSong record is deleted")
        @MainActor
        func orphanedFileDeleted() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            // Create a file with no corresponding SavedSong record.
            let orphanURL = mediaDir.appendingPathComponent("orphan.m4a")
            try Data("charlie delta".utf8).write(to: orphanURL)

            // Insert a song so the reconciler has something to work with,
            // but no SavedSong pointing to the orphan file.
            let song = insertSong(id: "orphanFileSong1", context: context)
            context.insert(Favourite(songID: song.id))

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        }
    }

    // MARK: - Transient state recovery

    @Suite("Transient state recovery")
    struct TransientStateRecoveryTests {

        @Test("pending SavedSong is moved to failed at launch")
        @MainActor
        func pendingSavedSongMovedToFailed() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "pendingSong1", context: context)
            let saved = SavedSong(
                songID: song.id,
                fileRelativePath: "pending.m4a",
                container: .m4a,
                codec: .aac,
                state: .pending
            )
            context.insert(saved)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<SavedSong>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .failed)
        }

        @Test("downloading SavedSong is moved to failed at launch")
        @MainActor
        func downloadingSavedSongMovedToFailed() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "downloadingSong1", context: context)
            let saved = SavedSong(
                songID: song.id,
                fileRelativePath: "downloading.m4a",
                container: .m4a,
                codec: .aac,
                state: .downloading,
                downloadedBytes: 512
            )
            context.insert(saved)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<SavedSong>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .failed)
            // downloadedBytes is reset so the UI shows a clean retry state.
            #expect(remaining[0].downloadedBytes == 0)
        }

        @Test("failed SavedSong is left as failed (not double-failed)")
        @MainActor
        func failedSavedSongLeftAsFailed() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "alreadyFailedSong1", context: context)
            let saved = SavedSong(
                songID: song.id,
                fileRelativePath: "failed.m4a",
                container: .m4a,
                codec: .aac,
                state: .failed,
                lastError: "Previous error"
            )
            context.insert(saved)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<SavedSong>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .failed)
        }
    }

    // MARK: - Queue: current → waiting at launch

    @Suite("Queue current-entry restore")
    struct QueueCurrentRestoreTests {

        @Test("current QueueEntry is restored to waiting at launch")
        @MainActor
        func currentEntryRestoredToWaiting() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "currentSong1", context: context)
            let entry = QueueEntry(songID: song.id, position: 0, state: .current)
            context.insert(entry)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<QueueEntry>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .waiting)
        }

        @Test("waiting QueueEntry is left as waiting")
        @MainActor
        func waitingEntryLeftAsWaiting() throws {
            let (context, mediaDir) = try makeTestEnvironment()
            defer { try? FileManager.default.removeItem(at: mediaDir) }

            let song = insertSong(id: "waitingSong1", context: context)
            let entry = QueueEntry(songID: song.id, position: 0, state: .waiting)
            context.insert(entry)

            let reconciler = StoreReconciler(context: context, mediaDirectoryURL: mediaDir)
            try reconciler.reconcile()

            let remaining = try context.fetch(FetchDescriptor<QueueEntry>())
            #expect(remaining.count == 1)
            #expect(remaining[0].state == .waiting)
        }
    }
}
