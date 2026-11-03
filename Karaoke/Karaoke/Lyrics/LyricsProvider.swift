// T072 — LyricsProvider protocol, LyricsQuery, LyricsError, LyricsProviderID.
//
// No error case means "not found" — absence is nil, not an error.
// Every error here is non-fatal: the performance proceeds with the video image.
//
// Satisfies: FR-022, FR-023, FR-024, contracts/lyrics-provider.md Protocol

import Foundation

// MARK: - LyricsProviderID

/// Stable identifier for a lyrics provider.
struct LyricsProviderID: RawRepresentable, Sendable, Hashable, Equatable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

extension LyricsProviderID {
    static let lrclib = LyricsProviderID(rawValue: "lrclib")
}

// MARK: - LyricsQuery

/// The query used to look up a lyrics track.
///
/// `durationSeconds` is required, not optional. Matching on title alone returns
/// the wrong song often enough that the duration check is the difference between
/// a useful feature and a confusing one (contracts/lyrics-provider.md).
struct LyricsQuery: Sendable {
    let title: String
    let artist: String?
    /// Used to reject a mismatched track. Required — see above.
    let durationSeconds: Int
}

// MARK: - LyricsError

/// Errors the lyrics provider can throw.
///
/// No case means "not found" — absence is `nil`, not an error.
/// Every case here is non-fatal: the performance proceeds with the video image.
/// A lyrics failure must never interrupt or delay playback.
enum LyricsError: Error, Sendable {
    case offline
    case rateLimited(retryAfter: TimeInterval?)
    case providerUnavailable(detail: String)
    case malformedResponse(detail: String)
    case timeout
}

// MARK: - LyricsProvider

/// The contract for a synchronized lyrics provider.
///
/// Nothing is fetched when `isEnabled` is false — the singer opts in
/// (contracts/lyrics-provider.md Behavioural requirements, FR-022).
protocol LyricsProvider: Sendable {
    var identifier: LyricsProviderID { get }

    /// Whether the singer has enabled this provider. Nothing is fetched otherwise.
    var isEnabled: Bool { get }

    /// Returns nil when no track is available — a normal, expected outcome,
    /// not an error. Most songs will have none.
    func lyrics(for query: LyricsQuery) async throws(LyricsError) -> LyricsTrackData?
}

// MARK: - LyricsTrackData

/// Parsed, validated lyrics data returned by a provider.
///
/// Distinct from the SwiftData `LyricsTrack` model — this is the in-memory
/// representation used by the timeline and the UI. The store layer converts
/// it to a `LyricsTrack` for persistence when needed.
struct LyricsTrackData: Sendable {
    let songID: String
    let source: LyricsSource
    let hasWordTiming: Bool
    let globalOffsetMs: Int
    let fetchedAt: Date
    let lines: [LyricsLineData]
}

struct LyricsLineData: Sendable {
    let index: Int
    let startMs: Int
    let endMs: Int?
    let text: String
    let words: [LyricsWordData]
}

struct LyricsWordData: Sendable {
    let lineIndex: Int
    let index: Int
    let startMs: Int
    let text: String
}
