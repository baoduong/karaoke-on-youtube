// T118 — QueueServiceTests.
//
// Tests for QueueService state transitions (data-model.md Queue Rules).
//
// Covered:
//   • Position contiguity after insert, remove, reorder (T110).
//   • Single-current invariant — at most one entry is `current` (T110).
//   • Natural advance: current → played, next waiting → current (T111).
//   • Failed-entry advance: current → failed, next waiting → current (T112).
//   • Current-removal advance: removing current advances as natural finish (T113).
//   • Non-current removal does not disturb current (T113).
//   • Launch restore: current is demoted to waiting (T114).
//
// Constitution Principle IV: queue transitions fail silently if broken —
// exactly the category that needs tests.
//
// Tests use an in-memory SwiftData container so they never touch the real store
// and run without a simulator.

import Testing
import Foundation
import SwiftData
@testable import Karaoke

// MARK: - Helpers

/// Creates an in-memory ModelContext for testing.
///
/// Uses the same schema as the production store so the models behave identically.
@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([
        Song.self,
        SavedSong.self,
        Favourite.self,
        QueueEntry.self,
        PerformanceSettings.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    return ModelContext(container)
}

/// Creates a QueueService backed by an in-memory context.
@MainActor
private func makeService() throws -> QueueService {
    let context = try makeContext()
    return QueueService(context: context)
}

// MARK: - QueueServiceTests

@Suite("QueueService")
struct QueueServiceTests {

    // MARK: - Position contiguity (T110)

    @Suite("Position contiguity")
    struct PositionContiguityTests {

        @Test("positions are zero-based and contiguous after three enqueues")
        @MainActor
        func contiguousAfterEnqueue() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            let positions = service.entries.map(\.position).sorted()
            #expect(positions == [0, 1, 2])
        }

        @Test("positions remain contiguous after removing the middle entry")
        @MainActor
        func contiguousAfterRemoveMiddle() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            let middleID = service.waiting[1].id
            service.remove(id: middleID)

            let positions = service.entries.map(\.position).sorted()
            #expect(positions == [0, 1])
        }

        @Test("positions remain contiguous after removing the first entry")
        @MainActor
        func contiguousAfterRemoveFirst() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            let firstID = service.waiting[0].id
            service.remove(id: firstID)

            let positions = service.entries.map(\.position).sorted()
            #expect(positions == [0, 1])
        }

        @Test("positions are unique — no duplicates")
        @MainActor
        func uniquePositions() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")
            service.enqueue(songID: "ddddddddddd")

            let positions = service.entries.map(\.position)
            let unique = Set(positions)
            #expect(positions.count == unique.count)
        }

        @Test("positions remain contiguous after reorder")
        @MainActor
        func contiguousAfterReorder() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            // Move last to first.
            service.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

            let positions = service.entries.map(\.position).sorted()
            #expect(positions == [0, 1, 2])
        }
    }

    // MARK: - Single-current invariant (T110)

    @Suite("Single-current invariant")
    struct SingleCurrentTests {

        @Test("at most one entry is current after multiple enqueues")
        @MainActor
        func atMostOneCurrent() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            let currentCount = service.entries.filter { $0.state == .current }.count
            #expect(currentCount <= 1)
        }

        @Test("at most one entry is current after natural advance")
        @MainActor
        func atMostOneCurrentAfterAdvance() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            // Manually set first to current to simulate playback starting.
            if let first = service.waiting.first {
                first.state = .current
            }
            service.currentFinished()

            let currentCount = service.entries.filter { $0.state == .current }.count
            #expect(currentCount <= 1)
        }
    }

    // MARK: - Natural advance (T111)

    @Suite("Natural advance")
    struct NaturalAdvanceTests {

        @Test("currentFinished marks current as played")
        @MainActor
        func currentBecomesPlayed() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            guard let first = service.waiting.first else {
                Issue.record("Expected at least one waiting entry")
                return
            }
            first.state = .current
            service.currentFinished()

            // The entry that was current is now played.
            let played = service.entries.filter { $0.state == .played }
            #expect(played.count == 1)
            #expect(played.first?.songID == "aaaaaaaaaaa")
        }

        @Test("currentFinished promotes the next waiting entry to current")
        @MainActor
        func nextWaitingBecomesCurrentOnFinish() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            guard let first = service.waiting.first else {
                Issue.record("Expected at least one waiting entry")
                return
            }
            first.state = .current
            service.currentFinished()

            // The second entry is now current.
            #expect(service.current?.songID == "bbbbbbbbbbb")
        }

        @Test("currentFinished with no remaining waiting entries leaves current nil")
        @MainActor
        func currentFinishedEmptyQueue() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")

            guard let only = service.waiting.first else {
                Issue.record("Expected one waiting entry")
                return
            }
            only.state = .current
            service.currentFinished()

            // Queue exhausted — no current entry.
            #expect(service.current == nil)
        }

        @Test("currentFinished promotes the lowest-positioned waiting entry")
        @MainActor
        func lowestPositionedWaitingBecomesCurrentOnFinish() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            guard let first = service.waiting.first else {
                Issue.record("Expected waiting entries")
                return
            }
            first.state = .current
            service.currentFinished()

            // The entry at position 1 (bbbbbbbbbbb) becomes current.
            #expect(service.current?.songID == "bbbbbbbbbbb")
        }
    }

    // MARK: - Failed-entry advance (T112)

    @Suite("Failed-entry advance")
    struct FailedEntryAdvanceTests {

        @Test("currentFailed marks current as failed")
        @MainActor
        func currentBecomesFailedOnError() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            guard let first = service.waiting.first else {
                Issue.record("Expected waiting entries")
                return
            }
            first.state = .current

            struct FakeError: Error {}
            service.currentFailed(FakeError())

            let failed = service.entries.filter { $0.state == .failed }
            #expect(failed.count == 1)
            #expect(failed.first?.songID == "aaaaaaaaaaa")
        }

        @Test("currentFailed advances to the next waiting entry")
        @MainActor
        func queueAdvancesAfterFailure() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            guard let first = service.waiting.first else {
                Issue.record("Expected waiting entries")
                return
            }
            first.state = .current

            struct FakeError: Error {}
            service.currentFailed(FakeError())

            // The second entry is now current — one dead song does not stall the party.
            #expect(service.current?.songID == "bbbbbbbbbbb")
        }

        @Test("currentFailed with no remaining waiting entries leaves current nil")
        @MainActor
        func failedWithEmptyQueueLeavesCurrentNil() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")

            guard let only = service.waiting.first else {
                Issue.record("Expected one waiting entry")
                return
            }
            only.state = .current

            struct FakeError: Error {}
            service.currentFailed(FakeError())

            #expect(service.current == nil)
        }
    }

    // MARK: - Current-removal advance (T113)

    @Suite("Current-removal advance")
    struct CurrentRemovalTests {

        @Test("removing the current entry advances to the next waiting entry")
        @MainActor
        func removingCurrentAdvancesQueue() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            guard let first = service.waiting.first else {
                Issue.record("Expected waiting entries")
                return
            }
            let currentID = first.id
            first.state = .current

            service.remove(id: currentID)

            // The second entry is now current.
            #expect(service.current?.songID == "bbbbbbbbbbb")
        }

        @Test("removing the current entry with no remaining waiting leaves current nil")
        @MainActor
        func removingCurrentWithEmptyQueueLeavesCurrentNil() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")

            guard let only = service.waiting.first else {
                Issue.record("Expected one waiting entry")
                return
            }
            let currentID = only.id
            only.state = .current

            service.remove(id: currentID)

            #expect(service.current == nil)
        }

        @Test("removing a non-current entry does not change the current entry")
        @MainActor
        func removingNonCurrentDoesNotDisturbCurrent() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")

            guard let first = service.waiting.first else {
                Issue.record("Expected waiting entries")
                return
            }
            first.state = .current
            let currentSongID = first.songID

            // Remove the last waiting entry (non-current).
            let lastWaiting = service.waiting.last
            if let lastID = lastWaiting?.id {
                service.remove(id: lastID)
            }

            // Current entry is unchanged.
            #expect(service.current?.songID == currentSongID)
        }
    }

    // MARK: - Launch restore (T114)

    @Suite("Launch restore")
    struct LaunchRestoreTests {

        @Test("restoreOnLaunch demotes current to waiting")
        @MainActor
        func currentDemotedToWaitingOnLaunch() throws {
            let context = try makeContext()
            // Persist a `current` entry directly to simulate a crash mid-session.
            let entry = QueueEntry(songID: "aaaaaaaaaaa", position: 0, state: .current)
            context.insert(entry)
            try context.save()

            // Create a new service instance (simulating a fresh launch) and restore.
            let service = QueueService(context: context)
            service.restoreOnLaunch()

            // The entry must be waiting, not current.
            #expect(service.current == nil)
            let waitingCount = service.entries.filter { $0.state == .waiting }.count
            #expect(waitingCount == 1)
        }

        @Test("restoreOnLaunch leaves waiting entries unchanged")
        @MainActor
        func waitingEntriesUnchangedOnLaunch() throws {
            let context = try makeContext()
            let entry = QueueEntry(songID: "aaaaaaaaaaa", position: 0, state: .waiting)
            context.insert(entry)
            try context.save()

            let service = QueueService(context: context)
            service.restoreOnLaunch()

            #expect(service.waiting.count == 1)
            #expect(service.waiting.first?.songID == "aaaaaaaaaaa")
        }

        @Test("restoreOnLaunch leaves played entries unchanged")
        @MainActor
        func playedEntriesUnchangedOnLaunch() throws {
            let context = try makeContext()
            let entry = QueueEntry(songID: "aaaaaaaaaaa", position: 0, state: .played)
            context.insert(entry)
            try context.save()

            let service = QueueService(context: context)
            service.restoreOnLaunch()

            let played = service.entries.filter { $0.state == .played }
            #expect(played.count == 1)
        }

        @Test("restoreOnLaunch with multiple current entries demotes all to waiting")
        @MainActor
        func multipleCurrrentDemotedOnLaunch() throws {
            // This is a defect state (at most one current is the invariant), but
            // restoreOnLaunch must handle it gracefully rather than crashing.
            let context = try makeContext()
            let entry1 = QueueEntry(songID: "aaaaaaaaaaa", position: 0, state: .current)
            let entry2 = QueueEntry(songID: "bbbbbbbbbbb", position: 1, state: .current)
            context.insert(entry1)
            context.insert(entry2)
            try context.save()

            let service = QueueService(context: context)
            service.restoreOnLaunch()

            #expect(service.current == nil)
            let waitingCount = service.entries.filter { $0.state == .waiting }.count
            #expect(waitingCount == 2)
        }
    }

    // MARK: - Reaching the end without advancing

    @Suite("Playing out without advancing")
    struct PlayedOutTests {

        @Test("the finished song is marked played")
        @MainActor
        func marksPlayed() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            let target = try #require(service.waiting.first)
            service.setCurrent(entryID: target.id, songID: target.songID)

            service.currentPlayedOut()

            let finished = try #require(
                service.entries.first { $0.songID == "aaaaaaaaaaa" }
            )
            #expect(finished.state == .played)
        }

        @Test("the next song is not promoted — nothing starts on its own")
        @MainActor
        func doesNotPromoteNext() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            let target = try #require(service.waiting.first)
            service.setCurrent(entryID: target.id, songID: target.songID)

            service.currentPlayedOut()

            #expect(service.current == nil)
            #expect(service.waiting.map(\.songID) == ["bbbbbbbbbbb"])
        }

        @Test("reaching the end with nothing current changes nothing")
        @MainActor
        func noCurrentIsNoOp() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")

            service.currentPlayedOut()

            #expect(service.waiting.count == 1)
            #expect(service.entries.allSatisfy { $0.state == .waiting })
        }
    }

    // MARK: - Reflecting what is playing

    @Suite("Reflecting what is playing")
    struct SetCurrentTests {

        @Test("tapping a waiting entry makes it current")
        @MainActor
        func promotesWaiting() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")

            let target = service.waiting[1]
            service.setCurrent(entryID: target.id, songID: target.songID)

            #expect(service.current?.songID == "bbbbbbbbbbb")
        }

        @Test("the abandoned song is recorded as skipped, not played")
        @MainActor
        func previousBecomesSkipped() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.currentFinished()

            let playing = try #require(service.current)
            #expect(playing.songID == "aaaaaaaaaaa")

            let target = try #require(service.waiting.first)
            service.setCurrent(entryID: target.id, songID: target.songID)

            let abandoned = try #require(
                service.entries.first { $0.songID == "aaaaaaaaaaa" }
            )
            #expect(abandoned.state == .skipped)
        }

        @Test("at most one entry is current after jumping")
        @MainActor
        func singleCurrentInvariant() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.enqueue(songID: "ccccccccccc")
            service.currentFinished()

            let target = try #require(service.waiting.last)
            service.setCurrent(entryID: target.id, songID: target.songID)

            let currentCount = service.entries.filter { $0.state == .current }.count
            #expect(currentCount == 1)
        }

        @Test("a played entry can be made current again")
        @MainActor
        func replaysFromHistory() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.currentFinished()
            service.currentFinished()

            let played = try #require(
                service.entries.first { $0.state == .played }
            )
            service.setCurrent(entryID: played.id, songID: played.songID)

            #expect(service.current?.id == played.id)
        }

        @Test("re-tapping the current entry leaves the queue untouched")
        @MainActor
        func retappingCurrentIsNoOp() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.currentFinished()

            let playing = try #require(service.current)
            service.setCurrent(entryID: playing.id, songID: playing.songID)

            #expect(service.current?.id == playing.id)
            #expect(service.waiting.count == 1)
        }

        @Test("playing a song that is not queued leaves no entry current")
        @MainActor
        func unqueuedSongClearsCurrent() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.currentFinished()
            #expect(service.current != nil)

            service.setCurrent(songID: "zzzzzzzzzzz")

            #expect(service.current == nil)
        }

        @Test("the song left behind by an unqueued start is skipped")
        @MainActor
        func unqueuedStartSkipsPrevious() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.currentFinished()

            service.setCurrent(songID: "zzzzzzzzzzz")

            let abandoned = try #require(
                service.entries.first { $0.songID == "aaaaaaaaaaa" }
            )
            #expect(abandoned.state == .skipped)
        }

        @Test("a queued song started from elsewhere takes over the badge")
        @MainActor
        func queuedSongMatchedBySongID() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "bbbbbbbbbbb")
            service.currentFinished()

            service.setCurrent(songID: "bbbbbbbbbbb")

            #expect(service.current?.songID == "bbbbbbbbbbb")
        }

        @Test("with the song queued twice, the tapped row is the one that lights up")
        @MainActor
        func duplicateSongUsesTappedRow() throws {
            let service = try makeService()
            service.enqueue(songID: "aaaaaaaaaaa")
            service.enqueue(songID: "aaaaaaaaaaa")

            let second = service.waiting[1]
            service.setCurrent(entryID: second.id, songID: second.songID)

            #expect(service.current?.id == second.id)
        }
    }
}
