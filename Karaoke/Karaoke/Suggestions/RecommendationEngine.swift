// T096 — RecommendationEngine: blending with concurrent deadline.
// T097 — Four exclusion rules.
// T098 — Suggestion validation.
//
// The engine NEVER THROWS. Total failure yields an empty list. A suggestion
// failure must never surface as an error during a performance (FR-025d).
//
// Blending order (recommendation-provider.md):
//   1. Gather candidates from each available strategy concurrently, under a
//      short overall deadline. A strategy that misses the deadline contributes
//      nothing and is not awaited.
//   2. Deduplicate by songID, keeping the highest-priority strategy's attribution.
//   3. Apply exclusion rules.
//   4. Rank by strategy priority, then by score within a strategy.
//   5. Truncate to the requested limit.
//
// Satisfies: FR-025a … FR-025f

import Foundation

// MARK: - ExclusionContext

/// Everything the engine needs to apply the four exclusion rules (T097).
struct ExclusionContext: Sendable {
    /// The currently playing song (exclusion rule 1).
    let currentSongID: SuggestionSongID?
    /// Songs already sung this session (exclusion rule 2 — FR-025c).
    /// This is the rule whose absence makes a suggestion list visibly stupid.
    let performedSongIDs: Set<SuggestionSongID>
    /// Songs already queued as `waiting` (exclusion rule 3).
    let waitingQueueSongIDs: Set<SuggestionSongID>
    /// Songs whose last resolution failed with a content-side error this session
    /// (exclusion rule 4).
    let contentFailedSongIDs: Set<SuggestionSongID>

    init(
        currentSongID: SuggestionSongID? = nil,
        performedSongIDs: Set<SuggestionSongID> = [],
        waitingQueueSongIDs: Set<SuggestionSongID> = [],
        contentFailedSongIDs: Set<SuggestionSongID> = []
    ) {
        self.currentSongID = currentSongID
        self.performedSongIDs = performedSongIDs
        self.waitingQueueSongIDs = waitingQueueSongIDs
        self.contentFailedSongIDs = contentFailedSongIDs
    }

    /// Returns true when a song ID should be excluded from suggestions.
    func shouldExclude(_ songID: SuggestionSongID) -> Bool {
        // Rule 1: the currently playing song.
        if let current = currentSongID, songID == current { return true }
        // Rule 2: every song in the session's performed set (FR-025c).
        if performedSongIDs.contains(songID) { return true }
        // Rule 3: songs already queued as waiting.
        if waitingQueueSongIDs.contains(songID) { return true }
        // Rule 4: songs whose last resolution failed with a content-side error.
        if contentFailedSongIDs.contains(songID) { return true }
        return false
    }
}

// MARK: - BlendedRecommendationEngine

/// Blends every available strategy, applies exclusions, ranks, truncates.
///
/// Never throws — a total failure yields an empty list (FR-025d).
///
/// The deadline is enforced with `withTaskGroup` + `Task.sleep`: each strategy
/// runs as a child task; the group collects results until the deadline fires,
/// then cancels remaining children. No fixed sleeps in tests — the deadline is
/// driven by a configurable `TimeInterval` so tests can inject a near-zero value.
final class BlendedRecommendationEngine: RecommendationEngine, @unchecked Sendable {

    /// Strategies in priority order. Index 0 = highest priority.
    private let providers: [any RecommendationProvider]

    /// How long to wait for all strategies before cutting off slow ones.
    /// FR-025d: the whole operation is bounded so a slow upstream cannot leave
    /// the suggestion area spinning while a song finishes.
    let deadline: TimeInterval

    init(
        providers: [any RecommendationProvider],
        deadline: TimeInterval = 3.0
    ) {
        self.providers = providers
        self.deadline = deadline
    }

    // MARK: RecommendationEngine

    func suggestions(for songID: SuggestionSongID,
                     excluding: Set<SuggestionSongID>,
                     limit: Int) async -> [Suggestion] {
        // Build the exclusion context from the caller-supplied set.
        // The caller is responsible for populating it from PlaybackSession.
        let exclusionContext = ExclusionContext(
            currentSongID: songID,
            performedSongIDs: excluding
        )
        return await suggestions(for: songID, context: exclusionContext, limit: limit)
    }

    /// Full-context variant used by PlayerViewModel (T101).
    func suggestions(
        for songID: SuggestionSongID,
        context: ExclusionContext,
        limit: Int
    ) async -> [Suggestion] {
        let available = providers.filter { $0.isAvailable }
        guard !available.isEmpty else { return [] }

        let deadlineNanos = UInt64(deadline * 1_000_000_000)
        let providerCount = available.count

        var allCandidates: [(priority: Int, suggestions: [Suggestion])] = []

        await withTaskGroup(of: (Int, [Suggestion]).self) { group in
            for (index, provider) in available.enumerated() {
                group.addTask {
                    do {
                        let results = try await provider.candidates(for: songID, limit: limit * 2)
                        return (index, results)
                    } catch {
                        return (index, [])
                    }
                }
            }

            // Deadline sentinel: index -1 signals the deadline fired.
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: deadlineNanos)
                } catch {
                    // Cancelled when all providers finished early — normal path.
                }
                return (-1, [])
            }

            var received = 0
            for await (index, results) in group {
                if index == -1 {
                    // Deadline fired before all providers finished.
                    group.cancelAll()
                    break
                }
                allCandidates.append((priority: index, suggestions: results))
                received += 1
                if received == providerCount {
                    // All providers finished before the deadline — cancel the sentinel.
                    group.cancelAll()
                    break
                }
            }
        }

        // Map provider index back to SuggestionStrategy priority.
        // available[index] corresponds to providers[index].
        var strategyForIndex: [Int: SuggestionStrategy] = [:]
        for (index, provider) in available.enumerated() {
            strategyForIndex[index] = strategyFromID(provider.identifier)
        }

        // Flatten and deduplicate by songID, keeping highest-priority strategy.
        // Sort by priority ascending (lower rawValue = higher priority) so the
        // first occurrence wins in the dedup map.
        let sorted = allCandidates.sorted { $0.priority < $1.priority }
        var seen: [SuggestionSongID: Suggestion] = [:]

        for (_, suggestions) in sorted {
            for suggestion in suggestions {
                if seen[suggestion.songID] == nil {
                    seen[suggestion.songID] = suggestion
                }
            }
        }

        // Apply exclusion rules (T097).
        let filtered = seen.values.filter { !context.shouldExclude($0.songID) }

        // Validate suggestions (T098).
        let valid = filtered.filter { isValid($0) }

        // Rank: strategy priority first, then score descending within strategy.
        let ranked = valid.sorted { lhs, rhs in
            if lhs.strategy != rhs.strategy {
                return lhs.strategy < rhs.strategy
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            // Deterministic tie-break by songID.
            return lhs.songID < rhs.songID
        }

        // Truncate to limit.
        return Array(ranked.prefix(limit))
    }

    // MARK: Private — validation (T098)

    /// Validate a suggestion before including it in the result.
    ///
    /// - `score` must be in 0…1.
    /// - `reason` must be non-empty.
    /// - `songID` must be non-empty.
    private func isValid(_ suggestion: Suggestion) -> Bool {
        guard !suggestion.songID.isEmpty else { return false }
        guard suggestion.score >= 0, suggestion.score <= 1 else { return false }
        guard !suggestion.reason.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return true
    }

    // MARK: Private — strategy ID mapping

    private func strategyFromID(_ id: StrategyID) -> SuggestionStrategy {
        switch id {
        case "sameChannel":    return .sameChannel
        case "coOccurrence":   return .coOccurrence
        case "history":        return .history
        case "favourite":      return .favourite
        default:               return .history
        }
    }
}

// MARK: - SuggestionsState

/// The state of the suggestions area, distinguishable from loading (T100).
enum SuggestionsState: Sendable, Equatable {
    /// Suggestions are being fetched.
    case loading
    /// Suggestions are available.
    case loaded([Suggestion])
    /// Cold start: no history and no upstream data. Explicitly not a loading state.
    /// The app says so plainly rather than rendering an empty list that looks like
    /// it is still loading (recommendation-provider.md Cold start, T100).
    case coldStart
    /// No song is currently playing.
    case idle
}
