import Foundation
import SwiftData

// MARK: - Supporting types

/// The audio container format of a saved rendition.
/// Mirrors the Container type used by AudioRendition (defined in Sources/).
/// Stored as a raw String so SwiftData can persist it without a separate enum table.
enum SavedContainer: String, Codable, Sendable {
    case m4a
    case webm
    case mp4
    case other

    /// AVFoundation infers a container from the path extension, so every file
    /// written to disk must carry a real one or decodability checks fail on
    /// valid audio. `other` falls back to m4a, the only container iOS is
    /// certain to decode.
    var pathExtension: String {
        switch self {
        case .m4a, .other: return "m4a"
        case .webm:        return "webm"
        case .mp4:         return "mp4"
        }
    }
}

/// The audio codec of a saved rendition.
/// Mirrors the Codec type used by AudioRendition (defined in Sources/).
enum SavedCodec: String, Codable, Sendable {
    case aac
    case opus
    case vorbis
    case other
}

/// State machine for a SavedSong download lifecycle.
///
/// Transitions (data-model.md SavedSong state machine):
/// ```
///   (none) ──start save──> pending ──> downloading ──> complete
///              │                │              │
///              │                │         ├─ no space ──> failed
///              │                │         ├─ network ───> failed
///              │                │         └─ cancelled ─> (none)
///              │                └─ cancelled ──────────> (none)
///                                    retry
///                          failed ──────────> pending
///                                    delete
///                         complete ──────────> (none)
/// ```
enum SaveState: String, Codable, Sendable {
    /// Download has been requested but not yet started.
    case pending
    /// Bytes are actively being written to the staging location.
    case downloading
    /// The file is on disk, verified, and decodable. Playback is available offline.
    case complete
    /// The download failed. `lastError` carries an actionable description.
    /// Retry moves back to `pending`.
    case failed
}

// MARK: - SavedSong

/// A Song whose selected rendition has been written to device storage (FR-029…FR-033).
///
/// One saved copy per Song — `songID` is the primary key.
///
/// Audio bytes stay out of the database. Only the relative path is stored so
/// the record survives reinstalls (data-model invariant: absolute paths break
/// across reinstalls).
@Model
final class SavedSong {

    // MARK: Stored properties

    /// Foreign key to Song. Primary key — one saved copy per Song.
    @Attribute(.unique) var songID: String

    /// Path relative to the app's media directory.
    ///
    /// Stored as a relative path, not an absolute path, so the record survives
    /// reinstalls and sandbox relocations (data-model.md SavedSong Rules).
    var fileRelativePath: String

    /// Container format copied from the saved AudioRendition.
    var container: SavedContainer

    /// Codec copied from the saved AudioRendition.
    var codec: SavedCodec

    /// Average bitrate copied from the saved AudioRendition.
    /// Lets FR-030 prove the offline copy matches the online quality.
    var averageBitrateBps: Int?

    /// Actual bytes on disk, measured after write — not the upstream estimate.
    /// Used for storage accounting (FR-031, data-model invariant 6).
    var byteSize: Int64

    /// When the save completed.
    var savedAt: Date

    /// Current state in the download lifecycle.
    var state: SaveState

    /// Bytes written so far. Equals `byteSize` when `state == .complete`.
    var downloadedBytes: Int64

    /// Populated only in `failed`. Cleared on retry.
    /// Must be actionable — the singer needs to know whether to free space or
    /// check their connection (FR-033).
    var lastError: String?

    // MARK: Init

    init(
        songID: String,
        fileRelativePath: String,
        container: SavedContainer,
        codec: SavedCodec,
        averageBitrateBps: Int? = nil,
        byteSize: Int64 = 0,
        savedAt: Date = Date(),
        state: SaveState = .pending,
        downloadedBytes: Int64 = 0,
        lastError: String? = nil
    ) {
        self.songID = songID
        self.fileRelativePath = fileRelativePath
        self.container = container
        self.codec = codec
        self.averageBitrateBps = averageBitrateBps
        self.byteSize = byteSize
        self.savedAt = savedAt
        self.state = state
        self.downloadedBytes = downloadedBytes
        self.lastError = lastError
    }
}
