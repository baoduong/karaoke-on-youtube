// T110-T114 — QueueService.
//
// Enforces every rule in data-model.md "Queue and QueueEntry":
//   • At most one entry is `current` at any time.
//   • `position` is contiguous and unique after every mutation.
//   • Natural finish: current → played, lowest-positioned waiting → current.
//   • Failure-tolerant: failed entry advances the queue (T112).
//   • Non-disruptive mutation: reorder/remove of non-current does not disturb
//     the current entry (T113). Removing current advances as natural finish.
//   • Launch restore: current is restored as waiting (T114).
//
// SEAM: This service has no dependency on AudioPipeline or PlaybackSession.
// The playback layer calls `currentFinished()` or `currentFailed(_:)` when
// appropriate. Queue logic is complete and testable in isolation.

import Foundation
import SwiftData
import os.log

// MARK: - QueueService

/// Manages the ordered list of songs awaiting performance.
///
/// All mutations run on the `@MainActor` so SwiftUI views observe changes
/// without explicit dispatching. The `ModelContext` is also main-actor-bound
/// in SwiftData's default configuration.
///
/// Caller-driven API (seam for playback integration):
/// - `currentFinished()` — natural end of the current song.
/// - `currentFailed(_:)` — resolution or playback failure; advances past it.
/// - `current` — the entry currently playing, or nil when idle.
@MainActor
@Observable
final class QueueService {

    // MARK: - Observable state

    /// All entries in position order. Includes played, skipped, and failed
    /// entries so the UI can show history.
    private(set) var entries: [QueueEntry] = []

    /// The entry currently playing. At most one at any time (data-model rule).
    var current: QueueEntry? {
        entries.first { $0.state == .current }
    }

    /// Entries still waiting to be played, in position order.
    var waiting: [QueueEntry] {
        entries.filter { $0.state == .waiting }.sorted { $0.position < $1.position }
    }

    // MARK: - Private

    private let context: ModelContext
    private static let log = Logger(subsystem: "com.karaoke.personal", category: "queue")

    // MARK: - Init

    /// Creates the service with the given SwiftData context.
    ///
    /// Call `restoreOnLaunch()` immediately after init to apply the
    /// launch-restore rule (T114): any persisted `current` entry becomes
    /// `waiting` so the app does not auto-resume audio on cold start.
    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Launch restore (T114)

    /// Applies the launch-restore rule: any `current` entry is demoted to
    /// `waiting` so the app does not auto-resume audio on cold start
    /// (data-model.md Queue Rules).
    ///
    /// Call once at app launch, before the UI is shown.
    func restoreOnLaunch() {
        loadEntries()
        for entry in entries where entry.state == .current {
            entry.state = .waiting
        }
        save()
        // Reload so `entries` reflects the restored state.
        loadEntries()
    }

    // MARK: - Queue mutations (T110, T113)

    /// Appends a new entry for `songID` at the end of the waiting list.
    ///
    /// Position is assigned as one past the current maximum, then the full
    /// list is renumbered to guarantee contiguity (T110).
    func enqueue(songID: String) {
        let nextPosition = (entries.map(\.position).max() ?? -1) + 1
        let entry = QueueEntry(songID: songID, position: nextPosition)
        context.insert(entry)
        loadEntries()
        renumber()
        save()
    }

    /// Removes the entry with the given id.
    ///
    /// - If the entry is `current`, advances exactly as a natural finish would
    ///   (data-model.md: "Removing the current entry advances exactly as a
    ///   natural finish would") — T113.
    /// - If the entry is non-current, the current entry is not disturbed — T113.
    func remove(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let wasCurrent = entry.state == .current
        context.delete(entry)
        loadEntries()
        renumber()
        save()
        if wasCurrent {
            advanceToNextWaiting()
        }
    }

    /// Moves entries at `source` offsets (within the waiting list) to `destination`.
    ///
    /// Only `waiting` entries participate in reordering. The `current` entry's
    /// position is not touched — non-disruptive mutation (T113).
    ///
    /// After the move, all positions are renumbered to stay contiguous (T110).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var waitingEntries = waiting
        waitingEntries.move(fromOffsets: source, toOffset: destination)
        // Assign new positions to waiting entries in their new order.
        // Non-waiting entries keep their existing positions; renumber() will
        // compact everything into a single contiguous sequence.
        for (index, entry) in waitingEntries.enumerated() {
            // Use a large offset to avoid collisions with non-waiting entries
            // before renumber() runs.
            entry.position = 10_000 + index
        }
        loadEntries()
        renumber()
        save()
    }

    // MARK: - Advance (T111, T112)

    /// Called by the playback layer when the current song ends naturally.
    ///
    /// The current entry becomes `played` and the lowest-positioned `waiting`
    /// entry becomes `current` (FR-026). If none remains, the queue is empty
    /// and the session ends cleanly (data-model.md Queue Rules).
    func currentFinished() {
        if let entry = current {
            entry.state = .played
        }
        save()
        advanceToNextWaiting()
    }

    /// Called by the playback layer when the current entry's resolution fails.
    ///
    /// The entry becomes `failed` and the queue advances — one dead song must
    /// not stall the party (data-model.md Queue Rules, spec edge case:
    /// *Source is withdrawn or restricted*) — T112.
    func currentFailed(_ error: Error) {
        if let entry = current {
            entry.state = .failed
            Self.log.error("queue: entry \(entry.id) failed — \(error.localizedDescription, privacy: .public)")
        }
        save()
        advanceToNextWaiting()
    }

    // MARK: - Private helpers

    /// Loads all QueueEntry records from the store, sorted by position.
    private func loadEntries() {
        let descriptor = FetchDescriptor<QueueEntry>(
            sortBy: [SortDescriptor(\.position)]
        )
        do {
            entries = try context.fetch(descriptor)
        } catch {
            Self.log.error("queue: fetch failed — \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    /// Renumbers all entries so `position` is zero-based, contiguous, and
    /// unique (data-model.md Queue Rules, T110).
    ///
    /// Ordering is preserved: entries are sorted by their current position
    /// before renumbering. This is called after every insert, remove, or
    /// reorder.
    private func renumber() {
        let sorted = entries.sorted { $0.position < $1.position }
        for (index, entry) in sorted.enumerated() {
            entry.position = index
        }
        // Reload so `entries` reflects the new positions.
        loadEntries()
    }

    /// Promotes the lowest-positioned `waiting` entry to `current`.
    ///
    /// If no waiting entry exists, the queue is empty and the session ends
    /// cleanly (data-model.md Queue Rules).
    private func advanceToNextWaiting() {
        loadEntries()
        guard let next = waiting.first else {
            // Queue exhausted — session ends cleanly.
            Self.log.info("queue: exhausted, session ends cleanly")
            save()
            return
        }
        next.state = .current
        save()
        loadEntries()
    }

    /// Persists pending changes to the SwiftData store.
    private func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("queue: save failed — \(error.localizedDescription, privacy: .public)")
        }
    }
}
