// T092 — SessionLog model for co-occurrence recording.
//
// Songs sung in the same past session are related by this group's actual taste,
// which no content-based signal captures. One local query and tends to produce
// the suggestions that feel uncanny in a good way (recommendation-provider.md).
//
// Persisted so co-occurrence data survives restarts.

import Foundation
import SwiftData

// MARK: - SessionLog

/// A record of one completed karaoke session.
///
/// Persisted so the coOccurrence strategy can relate songs across restarts.
/// Each session records which songs were performed together — the signal that
/// captures this group's actual taste.
@Model
final class SessionLog {

    // MARK: Stored properties

    /// Unique session identifier.
    @Attribute(.unique) var sessionID: String

    /// When the session started.
    var startedAt: Date

    /// When the session ended (nil if still in progress).
    var endedAt: Date?

    /// The song IDs performed in this session, in order.
    ///
    /// Stored as a comma-separated string because SwiftData does not support
    /// arrays of scalars as a first-class attribute in all versions.
    var performedSongIDsRaw: String

    // MARK: Computed

    /// The song IDs performed in this session.
    var performedSongIDs: [String] {
        get {
            performedSongIDsRaw
                .split(separator: ",", omittingEmptySubsequences: true)
                .map(String.init)
        }
        set {
            performedSongIDsRaw = newValue.joined(separator: ",")
        }
    }

    // MARK: Init

    init(
        sessionID: String = UUID().uuidString,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        performedSongIDs: [String] = []
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.performedSongIDsRaw = performedSongIDs.joined(separator: ",")
    }
}

// MARK: - SessionLog helpers

extension SessionLog {

    /// Record that a song was performed in this session.
    func recordPerformed(songID: String) {
        var ids = performedSongIDs
        if !ids.contains(songID) {
            ids.append(songID)
            performedSongIDs = ids
        }
    }

    /// Returns the set of song IDs that co-occurred with the given song in this session.
    func coOccurrences(with songID: String) -> Set<String> {
        let ids = performedSongIDs
        guard ids.contains(songID) else { return [] }
        return Set(ids).subtracting([songID])
    }
}
