import Foundation
import SwiftData

// MARK: - QueueEntryState

/// State of a single queue entry.
///
/// At most one entry is `current` at any time (data-model.md Queue Rules).
/// On launch, any `current` entry is restored as `waiting` — the app does not
/// auto-resume audio on cold start.
enum QueueEntryState: String, Codable, Sendable {
    /// Waiting to be played.
    case waiting
    /// Currently playing. At most one entry is in this state at any time.
    case current
    /// Playback completed naturally.
    case played
    /// Singer skipped this entry.
    case skipped
    /// Resolution failed; the queue advanced past this entry automatically.
    /// One dead song must not stall the party (spec edge case: Source is
    /// withdrawn or restricted).
    case failed
}

// MARK: - QueueEntry

/// One entry in the ordered list of Songs awaiting performance (FR-025, FR-026).
///
/// `id` is the entry's own identity — the same Song may appear twice in one
/// queue (e.g. a crowd favourite requested again). `songID` is the foreign key
/// to the Song.
///
/// `position` is zero-based and must be contiguous and unique within the Queue.
/// StoreReconciler and QueueService are responsible for keeping it so; a gap or
/// duplicate is a defect (data-model.md Queue Rules).
@Model
final class QueueEntry {

    // MARK: Stored properties

    /// Own identity. The same Song may appear twice in one queue.
    var id: UUID

    /// Foreign key to Song.
    var songID: String

    /// Zero-based position within the Queue. Contiguous and unique.
    ///
    /// Renumbered to stay contiguous after every insert, remove, or reorder.
    /// A gap or duplicate is a defect (data-model.md Queue Rules).
    var position: Int

    /// When this entry was added to the queue.
    var addedAt: Date

    /// Current state in the queue lifecycle.
    var state: QueueEntryState

    // MARK: Init

    init(
        id: UUID = UUID(),
        songID: String,
        position: Int,
        addedAt: Date = Date(),
        state: QueueEntryState = .waiting
    ) {
        self.id = id
        self.songID = songID
        self.position = position
        self.addedAt = addedAt
        self.state = state
    }
}
