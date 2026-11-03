import Foundation
import SwiftData

// MARK: - Song

/// A karaoke source the singer can perform. The anchor entity — search results,
/// queue entries, favourites, and saved songs all reference it.
///
/// Persistence: a Song is retained only while referenced by a Favourite,
/// QueueEntry, or SavedSong. Unreferenced Songs are removed at launch by
/// StoreReconciler (data-model invariant 2).
@Model
final class Song {

    // MARK: Stored properties

    /// Upstream video identifier. Primary key. Stable across sessions.
    /// Validated at parse time — malformed ids are never persisted (T017).
    @Attribute(.unique) var id: String

    /// As reported upstream. Not normalised — the singer searches for what they saw.
    var title: String

    /// Uploader. The main signal for whether a result is a real karaoke channel.
    var channelName: String

    /// Used for queue time estimates and to reject absurd results.
    /// Must be > 0; zero or negative means the upstream metadata is unusable.
    /// Values > 3600 are flagged but not rejected — long compilations are
    /// legitimate (data-model.md Song Validation, spec edge case: Very long source).
    var durationSeconds: Int

    /// Remote thumbnail. Cached by the image layer, not by this model.
    var thumbnailURL: URL?

    /// Set on first local persistence. Used for unreferenced-cleanup diagnostics.
    var firstSeenAt: Date

    /// Null until first played. Drives "recently sung".
    var lastPlayedAt: Date?

    /// Incremented when playback passes the halfway point, not on mere selection
    /// (FR-061 / T061). Defaults to 0.
    var playCount: Int

    // MARK: Init

    init(
        id: String,
        title: String,
        channelName: String,
        durationSeconds: Int,
        thumbnailURL: URL? = nil,
        firstSeenAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        playCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.channelName = channelName
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.firstSeenAt = firstSeenAt
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
    }
}

// MARK: - Validation (T017)

extension Song {

    /// Errors produced when upstream metadata fails validation.
    /// A malformed id is rejected at parse time and never reaches the store.
    enum ValidationError: Error, Sendable {
        /// The video identifier is empty or does not match the expected shape.
        case malformedID(String)
        /// `durationSeconds` is zero or negative — the metadata is unusable.
        case nonPositiveDuration(Int)
        /// `title` is empty after trimming.
        case emptyTitle
        /// `channelName` is empty after trimming.
        case emptyChannelName
    }

    /// Whether this song's duration exceeds one hour.
    ///
    /// Values > 3600 are flagged, not rejected — long compilations are
    /// legitimate but trigger the bounded-resolution path (spec edge case:
    /// *Very long source*). Callers should surface this to the user.
    var isLongSource: Bool { durationSeconds > 3600 }

    /// Validates a candidate Song before it is persisted.
    ///
    /// - Parameter id: The upstream video identifier to validate.
    /// - Parameter title: Song title as reported upstream.
    /// - Parameter channelName: Uploader name.
    /// - Parameter durationSeconds: Duration in seconds.
    /// - Throws: `ValidationError` describing the first rule that fails.
    ///
    /// Call this at parse time, before constructing a `Song` instance.
    /// A malformed id must never reach the store (data-model.md Song Validation).
    static func validate(
        id: String,
        title: String,
        channelName: String,
        durationSeconds: Int
    ) throws {
        // id: non-empty and matching the upstream identifier shape.
        // YouTube video IDs are 11 characters of [A-Za-z0-9_-].
        // A malformed id is rejected at parse time, never persisted.
        guard !id.isEmpty, isValidYouTubeID(id) else {
            throw ValidationError.malformedID(id)
        }

        // durationSeconds > 0. Zero or negative means the upstream metadata is
        // unusable; the result is dropped from search output rather than shown.
        guard durationSeconds > 0 else {
            throw ValidationError.nonPositiveDuration(durationSeconds)
        }

        // title non-empty after trimming.
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.emptyTitle
        }

        // channelName non-empty after trimming.
        guard !channelName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.emptyChannelName
        }

        // durationSeconds > 3600 is flagged, not rejected — handled by
        // `isLongSource` on the resulting model instance.
    }

    /// Returns true when `id` matches the YouTube video identifier shape:
    /// exactly 11 characters from [A-Za-z0-9_-].
    ///
    /// This is the documented stable format for YouTube video IDs. Rejecting
    /// anything that does not match prevents garbage from reaching the store
    /// without requiring a network round-trip.
    private static func isValidYouTubeID(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Sendable

// @Model classes are reference types managed by SwiftData's model context.
// Song is not Sendable across actor boundaries; callers must access it on the
// ModelContext's actor. No explicit conformance is added here.
