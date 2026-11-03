// T105 — Engine never-throws tests.
//
// With every strategy failing, the engine returns an empty list rather than
// propagating an error (recommendation-provider.md: "The engine never throws").
// FR-025d: a suggestion failure must not surface as an error during a performance.

import Foundation
import Testing
@testable import Karaoke

@Suite("Engine Resilience — Never Throws")
struct EngineResilienceTests {

    // MARK: - Helpers

    /// A provider that always throws.
    private struct AlwaysFailingProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true
        let error: RecommendationError

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            throw error
        }
    }

    /// A provider that is unavailable.
    private struct UnavailableProvider: RecommendationProvider {
        let identifier: StrategyID = "unavailable"
        let isAvailable: Bool = false

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            throw RecommendationError.strategyUnavailable
        }
    }

    // MARK: - Never throws

    @Test("Engine returns empty list when all strategies fail with strategyUnavailable")
    func allStrategiesUnavailableYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(
            providers: [
                AlwaysFailingProvider(identifier: "p1", error: .strategyUnavailable),
                AlwaysFailingProvider(identifier: "p2", error: .strategyUnavailable),
            ],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty, "All-failing engine must return empty list, not throw")
    }

    @Test("Engine returns empty list when all strategies fail with upstreamFailed")
    func allStrategiesUpstreamFailedYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(
            providers: [
                AlwaysFailingProvider(identifier: "p1", error: .upstreamFailed(detail: "network error")),
                AlwaysFailingProvider(identifier: "p2", error: .upstreamFailed(detail: "timeout")),
            ],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty)
    }

    @Test("Engine returns empty list when all strategies fail with timedOut")
    func allStrategiesTimedOutYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(
            providers: [
                AlwaysFailingProvider(identifier: "p1", error: .timedOut),
            ],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty)
    }

    @Test("Engine returns empty list when all strategies fail with rateLimited")
    func allStrategiesRateLimitedYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(
            providers: [
                AlwaysFailingProvider(identifier: "p1", error: .rateLimited(retryAfter: 60)),
            ],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty)
    }

    @Test("Engine returns empty list when no providers are available")
    func noAvailableProvidersYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(
            providers: [UnavailableProvider()],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty)
    }

    @Test("Engine returns empty list when provider list is empty")
    func emptyProviderListYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(providers: [], deadline: 5.0)

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty)
    }

    @Test("One failing strategy does not prevent others from contributing")
    func oneFailingDoesNotBlockOthers() async {
        let failing = AlwaysFailingProvider(
            identifier: "sameChannel",
            error: .upstreamFailed(detail: "network error")
        )

        struct WorkingProvider: RecommendationProvider {
            let identifier: StrategyID = "history"
            let isAvailable: Bool = true
            func candidates(for songID: SuggestionSongID,
                            limit: Int) async throws(RecommendationError) -> [Suggestion] {
                [Suggestion(songID: "historySong1", strategy: .history, score: 0.8)]
            }
        }

        let engine = BlendedRecommendationEngine(
            providers: [failing, WorkingProvider()],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            excluding: [],
            limit: 10
        )

        #expect(!results.isEmpty, "Working strategy must contribute even when another fails")
        #expect(results.first?.songID == "historySong1")
    }
}
