// T091 — RecommendationProvider protocol, RecommendationEngine protocol,
// Suggestion type, SuggestionStrategy enum, RecommendationError.
//
// Satisfies: FR-025a … FR-025f
// Contract: contracts/recommendation-provider.md

import Foundation

// MARK: - Type aliases

/// Stable upstream video identifier, same shape as SongID in SourceProvider.
typealias SuggestionSongID = String

/// Stable identifier for a recommendation strategy.
typealias StrategyID = String

// MARK: - SuggestionStrategy

/// Which source produced a suggestion. Surfaced to the singer (FR-025f).
///
/// Priority order matches the blending rule in recommendation-provider.md:
/// upstreamRelated (cancelled, retained for future) → sameChannel → coOccurrence → history → favourite.
enum SuggestionStrategy: Int, Sendable, Comparable, CaseIterable {
    /// The platform's own "what's next" data. Cancelled by Spike S8 — enum case
    /// retained so the strategy can be added later without a contract change.
    case upstreamRelated = 0
    /// More from the same karaoke channel.
    case sameChannel = 1
    /// Sung in the same session as the current song previously.
    case coOccurrence = 2
    /// The singer sang it before and liked it (play count + recency).
    case history = 3
    /// An unplayed favourite.
    case favourite = 4

    static func < (lhs: SuggestionStrategy, rhs: SuggestionStrategy) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short, singer-facing reason string (FR-025f).
    var defaultReason: String {
        switch self {
        case .upstreamRelated: return "suggested by the platform"
        case .sameChannel:     return "more from this channel"
        case .coOccurrence:    return "often sung together"
        case .history:         return "you sang this before"
        case .favourite:       return "one of your favourites"
        }
    }
}

// MARK: - Suggestion

/// A candidate next song for the song currently playing (FR-025a … FR-025f).
///
/// Transient — regenerated whenever the current song changes, never persisted.
/// Caching would make suggestions stale against a session-exclusion set that
/// changes every few minutes (data-model.md Suggestion).
struct Suggestion: Sendable, Equatable {
    /// Foreign key to a Song.
    let songID: SuggestionSongID
    /// Which source produced it. Surfaced to the singer (FR-025f).
    let strategy: SuggestionStrategy
    /// 0…1 within its strategy. Used for ranking, not shown.
    let score: Double
    /// Short, singer-facing reason. Non-empty (data-model.md Suggestion Validation).
    let reason: String

    init(songID: SuggestionSongID, strategy: SuggestionStrategy, score: Double, reason: String? = nil) {
        self.songID = songID
        self.strategy = strategy
        self.score = score
        self.reason = reason ?? strategy.defaultReason
    }
}

// MARK: - RecommendationError

/// Errors a strategy may throw. The engine absorbs every one — no
/// RecommendationError reaches the singer (FR-025d).
enum RecommendationError: Error, Sendable {
    case strategyUnavailable
    case upstreamFailed(detail: String)
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
}

// MARK: - RecommendationProvider

/// A single recommendation strategy.
///
/// Returns [] freely — an empty result from one strategy is normal and is
/// covered by the others (recommendation-provider.md Protocol).
protocol RecommendationProvider: Sendable {
    var identifier: StrategyID { get }
    var isAvailable: Bool { get }

    /// Candidates for the given song.
    ///
    /// - Parameters:
    ///   - songID: The song currently playing.
    ///   - limit: Maximum candidates to return.
    /// - Returns: Candidate suggestions, possibly empty.
    /// - Throws: `RecommendationError` — absorbed by the engine, never shown.
    func candidates(for songID: SuggestionSongID,
                    limit: Int) async throws(RecommendationError) -> [Suggestion]
}

// MARK: - RecommendationEngine

/// Blends every available strategy, applies exclusions, ranks, truncates.
///
/// Never throws: a total failure yields an empty list, which the UI shows as
/// "no suggestions", never as an error (FR-025d).
protocol RecommendationEngine: Sendable {
    func suggestions(for songID: SuggestionSongID,
                     excluding: Set<SuggestionSongID>,
                     limit: Int) async -> [Suggestion]
}
