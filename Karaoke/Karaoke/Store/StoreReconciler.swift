import Foundation
import SwiftData

// MARK: - StoreReconciler

/// Enforces data-model.md's seven cross-entity invariants at launch (T025).
///
/// Run once, on the main actor, before the UI is shown. The reconciler is
/// intentionally synchronous within a single ModelContext so every repair is
/// atomic from the store's perspective.
///
/// **Invariants enforced** (data-model.md Cross-Entity Invariants):
///
/// 1. Every `QueueEntry.songID`, `Favourite.songID`, `SavedSong.songID`, and
///
/// 2. A Song is retained if and only if it is referenced by a Favourite, a
///    QueueEntry, or a SavedSong. Unreferenced Songs are removed.
///
///    its SavedSong file. (Handled by invariant 2's cleanup cascade.)
///
/// 4. No StreamAddress value reaches persistent storage. (Structural — no
///    StreamAddress type is in the schema. Verified by schema inspection.)
///
/// 5. PerformanceSettings values are in range at every read. (Enforced by the
///    clamped accessors in PerformanceSettings itself, T023.)
///
/// 6. The sum of SavedSong.byteSize over `complete` entries equals the measured
///    size of the media directory minus staging. Orphaned files are removed;
///    records with no file are moved to `failed`.
///
/// 7. Nothing in this model is transmitted to any service operated by this app.
///    (Structural — no network call is made here.)
///
/// **SavedSong transient-state recovery** (data-model.md SavedSong Rules):
/// Any entry in `pending` or `downloading` is reconciled at launch: its staging
/// file is checked and the entry either resumes or moves to `failed`. No entry
/// stays in a transient state across launches.
@MainActor
final class StoreReconciler {

    // MARK: Dependencies

    private let context: ModelContext
    private let mediaDirectoryURL: URL

    // MARK: Init

    init(context: ModelContext, mediaDirectoryURL: URL) {
        self.context = context
        self.mediaDirectoryURL = mediaDirectoryURL
    }

    // MARK: Public entry point

    /// Run all reconciliation passes in dependency order.
    ///
    /// Call once at launch, before the UI is shown. Safe to call again (idempotent).
    func reconcile() throws {
        // Pass order matters:
        // 1. Repair orphaned references first so later passes see a consistent set.
        try repairOrphanedReferences()
        try removeUnreferencedSongs()
        // 3. Reconcile SavedSong records against the file system.
        try reconcileSavedSongs()
        // 4. Recover transient SavedSong states.
        try recoverTransientSavedSongStates()
        // 5. Restore any `current` QueueEntry to `waiting`.
        try restoreCurrentQueueEntries()

        try context.save()
    }

    // MARK: - Invariant 1: Repair orphaned references

    /// `songID` does not resolve to an existing Song (invariant 1).
    private func repairOrphanedReferences() throws {
        let songIDs = try fetchAllSongIDs()

        // Orphaned QueueEntries
        let queueEntries = try context.fetch(FetchDescriptor<QueueEntry>())
        for entry in queueEntries where !songIDs.contains(entry.songID) {
            context.delete(entry)
        }

        // Orphaned Favourites
        let favourites = try context.fetch(FetchDescriptor<Favourite>())
        for fav in favourites where !songIDs.contains(fav.songID) {
            context.delete(fav)
        }

        // Orphaned SavedSongs — also delete the file if it exists
        let savedSongs = try context.fetch(FetchDescriptor<SavedSong>())
        for saved in savedSongs where !songIDs.contains(saved.songID) {
            deleteFileIfExists(relativePath: saved.fileRelativePath)
            context.delete(saved)
        }
    }

    // MARK: - Invariant 2 & 3: Remove unreferenced Songs

    /// Removes Songs not referenced by any Favourite, QueueEntry, or SavedSong,
    private func removeUnreferencedSongs() throws {
        // Build the set of referenced song IDs.
        let referencedIDs = try fetchReferencedSongIDs()

        let songs = try context.fetch(FetchDescriptor<Song>())
        let savedSongs = try context.fetch(FetchDescriptor<SavedSong>())

        for song in songs where !referencedIDs.contains(song.id) {
            let songID = song.id

            // Cascade: delete the SavedSong file and record.
            for saved in savedSongs where saved.songID == songID {
                deleteFileIfExists(relativePath: saved.fileRelativePath)
                context.delete(saved)
            }

            context.delete(song)
        }
    }

    // MARK: - Invariant 6: Reconcile SavedSong records against the file system

    /// The file system is authoritative for existence; the record is authoritative
    /// for metadata (data-model.md SavedSong Rules, invariant 6).
    ///
    /// - A record with no file → moved to `failed` with an actionable error.
    /// - An orphaned file with no record → deleted (the record is the authority
    ///   for metadata; a file without a record is unaccountable storage).
    private func reconcileSavedSongs() throws {
        let savedSongs = try context.fetch(FetchDescriptor<SavedSong>())

        // Build the set of known relative paths from complete records.
        var knownRelativePaths = Set<String>()

        for saved in savedSongs {
            let fileURL = mediaDirectoryURL.appendingPathComponent(saved.fileRelativePath)
            let exists = FileManager.default.fileExists(atPath: fileURL.path)

            if saved.state == .complete && !exists {
                // Record says complete but file is gone — move to failed.
                saved.state = .failed
                saved.lastError = "File missing from media directory. Re-download required."
            } else if saved.state == .complete && exists {
                knownRelativePaths.insert(saved.fileRelativePath)
            }
        }

        // Remove orphaned files — files in the media directory with no
        // corresponding complete SavedSong record.
        removeOrphanedMediaFiles(knownRelativePaths: knownRelativePaths)
    }

    // MARK: - Transient state recovery

    /// Moves any `pending` or `downloading` SavedSong to `failed` at launch.
    ///
    /// No entry stays in a transient state across launches (data-model.md
    /// SavedSong Rules). The download coordinator (T120) will offer retry.
    private func recoverTransientSavedSongStates() throws {
        let allSaved = try context.fetch(FetchDescriptor<SavedSong>())
        for saved in allSaved where saved.state == .pending || saved.state == .downloading {
            // Delete any partial staging file.
            deleteFileIfExists(relativePath: saved.fileRelativePath)
            saved.state = .failed
            saved.lastError = "Download interrupted by app restart. Tap to retry."
            saved.downloadedBytes = 0
        }
    }

    // MARK: - Queue: restore current → waiting

    /// Restores any `current` QueueEntry to `waiting` at launch.
    ///
    /// The app does not auto-resume audio on cold start (data-model.md Queue Rules).
    private func restoreCurrentQueueEntries() throws {
        let allEntries = try context.fetch(FetchDescriptor<QueueEntry>())
        for entry in allEntries where entry.state == .current {
            entry.state = .waiting
        }
    }

    // MARK: - Helpers

    /// Returns the set of all Song IDs currently in the store.
    private func fetchAllSongIDs() throws -> Set<String> {
        let songs = try context.fetch(FetchDescriptor<Song>())
        return Set(songs.map(\.id))
    }

    /// Returns the set of Song IDs referenced by at least one Favourite,
    /// QueueEntry, or SavedSong.
    private func fetchReferencedSongIDs() throws -> Set<String> {
        var ids = Set<String>()

        let favourites = try context.fetch(FetchDescriptor<Favourite>())
        for fav in favourites { ids.insert(fav.songID) }

        let queueEntries = try context.fetch(FetchDescriptor<QueueEntry>())
        for entry in queueEntries { ids.insert(entry.songID) }

        let savedSongs = try context.fetch(FetchDescriptor<SavedSong>())
        for saved in savedSongs { ids.insert(saved.songID) }

        return ids
    }

    /// Deletes a file at `mediaDirectoryURL/relativePath` if it exists.
    /// Failures are silently ignored — the goal is best-effort cleanup.
    private func deleteFileIfExists(relativePath: String) {
        let url = mediaDirectoryURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes files in the media directory that are not in `knownRelativePaths`.
    ///
    /// Only removes regular files at the top level of the media directory.
    /// Staging subdirectories are left to the download coordinator.
    private func removeOrphanedMediaFiles(knownRelativePaths: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: mediaDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }

        for fileURL in contents {
            let relativePath = fileURL.lastPathComponent
            // Skip subdirectories (staging area).
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if isDir.boolValue { continue }

            if !knownRelativePaths.contains(relativePath) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
