import Foundation
import SwiftData

// MARK: - LyricsSource

/// Which provider supplied the lyrics track. Needed to re-fetch or invalidate.
enum LyricsSource: String, Codable, Sendable {
    /// Fetched from lrclib.net (FR-022).
    case lrclib
    /// Embedded in the video metadata.
    case embedded
    /// Manually entered by the singer.
    case manual
}

// MARK: - LyricsTrack

/// Optional synchronized text for a Song (FR-022, FR-023).
///
/// A Song may have none — most karaoke sources carry the words in the video
/// image, which is handled by the video layer, not by this model.
///
/// One track per Song (`songID` is the foreign key).
/// Persisted only for SavedSong; for streamed songs the track is in-memory only
/// (data-model.md persistence boundary).
@Model
final class LyricsTrack {

    // MARK: Stored properties

    /// Foreign key to Song. One track per Song.
    var songID: String

    /// Which provider supplied this track. Needed to re-fetch or invalidate.
    var source: LyricsSource

    /// False means line-level highlight only; true means word-by-word karaoke
    /// highlighting is available.
    var hasWordTiming: Bool

    /// Singer-adjustable correction for a track that is uniformly early or late.
    /// Default 0. Added to the effective lookup time alongside
    /// `PerformanceSettings.manualLyricsOffsetMs` and the route's output latency
    /// (data-model.md Timing Rules, FR-023).
    var globalOffsetMs: Int

    /// When this track was fetched from the provider.
    var fetchedAt: Date

    /// The lines of this track, ordered by `index`.
    @Relationship(deleteRule: .cascade) var lines: [LyricsLine]

    // MARK: Init

    init(
        songID: String,
        source: LyricsSource,
        hasWordTiming: Bool,
        globalOffsetMs: Int = 0,
        fetchedAt: Date = Date(),
        lines: [LyricsLine] = []
    ) {
        self.songID = songID
        self.source = source
        self.hasWordTiming = hasWordTiming
        self.globalOffsetMs = globalOffsetMs
        self.fetchedAt = fetchedAt
        self.lines = lines
    }
}

// MARK: - LyricsLine

/// One line of a LyricsTrack.
///
/// `startMs` must be strictly increasing across `index` within a track.
/// A track that is not monotonic is rejected at parse time rather than
/// producing jumping highlights (data-model.md LyricsTrack Validation).
///
/// An empty `text` is a legitimate instrumental-gap marker — it is NOT a
/// validation failure (data-model.md LyricsTrack Validation).
@Model
final class LyricsLine {

    // MARK: Stored properties

    /// Zero-based, ordered within the track.
    var index: Int

    /// Milliseconds from song start, before `globalOffsetMs` is applied.
    /// Must be strictly increasing across `index`.
    var startMs: Int

    /// End time in milliseconds. Null means "until the next line starts".
    /// When present: must be > `startMs` and ≤ the next line's `startMs`.
    var endMs: Int?

    /// The text of this line. May be empty — an empty line is a legitimate
    /// instrumental-gap marker (data-model.md LyricsLine).
    var text: String

    /// Words within this line. Present only when `LyricsTrack.hasWordTiming`.
    @Relationship(deleteRule: .cascade) var words: [LyricsWord]

    // MARK: Init

    init(
        index: Int,
        startMs: Int,
        endMs: Int? = nil,
        text: String,
        words: [LyricsWord] = []
    ) {
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.words = words
    }
}

// MARK: - LyricsWord

/// One word within a LyricsLine. Present only when `LyricsTrack.hasWordTiming`.
///
/// `startMs` must be strictly increasing within a line and within the enclosing
/// line's bounds (data-model.md LyricsWord Validation).
/// `text` must be non-empty — an empty word is not a legitimate marker.
@Model
final class LyricsWord {

    // MARK: Stored properties

    /// Foreign key to LyricsLine (by `index`).
    var lineIndex: Int

    /// Zero-based within the line.
    var index: Int

    /// Milliseconds from song start. Must be strictly increasing within the line
    /// and within the enclosing line's bounds.
    var startMs: Int

    /// The word text. Non-empty (data-model.md LyricsWord).
    var text: String

    // MARK: Init

    init(lineIndex: Int, index: Int, startMs: Int, text: String) {
        self.lineIndex = lineIndex
        self.index = index
        self.startMs = startMs
        self.text = text
    }
}
