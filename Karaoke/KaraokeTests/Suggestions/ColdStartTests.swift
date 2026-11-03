// T108 — Cold-start tests.
//
// An empty store with no upstream yields an empty list and the explicit
// no-suggestions state, distinguishable from a loading state
// (recommendation-provider.md Cold start, T100).
//
// Cold start is the one case where FR-025b cannot be satisfied. It resolves
// itself after the first few songs.

import Foundation
import Testing
@testable import Karaoke

@Suite("Cold Start")
struct ColdStartTests {

    // MARK: - Helpers

    /// A provider that always returns empty (simulates no data).
    private struct EmptyProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            []
        }
    }

    /// A provider that is unavailable (simulates upstream disabled).
    private struct UnavailableProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = false

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            throw RecommendationError.strategyUnavailable
        }
    }

    // MARK: - Cold start: engine returns empty

    @Test("Empty store with no upstream yields empty list")
    func emptyStoreYieldsEmptyList() async {
        let engine = BlendedRecommendationEngine(
            providers: [
                UnavailableProvider(identifier: "sameChannel"),
                EmptyProvider(identifier: "coOccurrence"),
                EmptyProvider(identifier: "history"),
                EmptyProvider(identifier: "favourite"),
            ],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(results.isEmpty, "Cold start must yield an empty list")
    }

    @Test("Empty store with all unavailable providers yields empty list")
    func allUnavailableYieldsEmpty() async {
        let engine = BlendedRecommendationEngine(
            providers: [
                UnavailableProvider(identifier: "sameChannel"),
                UnavailableProvider(identifier: "coOccurrence"),
                UnavailableProvider(identifier: "history"),
                UnavailableProvider(identifier: "favourite"),
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

    // MARK: - SuggestionsState distinguishability

    @Test("coldStart state is not equal to loading state")
    func coldStartDistinguishableFromLoading() {
        let coldStart = SuggestionsState.coldStart
        let loading = SuggestionsState.loading

        #expect(coldStart != loading,
                "coldStart must be distinguishable from loading (T100)")
    }

    @Test("coldStart state is not equal to idle state")
    func coldStartDistinguishableFromIdle() {
        let coldStart = SuggestionsState.coldStart
        let idle = SuggestionsState.idle

        #expect(coldStart != idle)
    }

    @Test("loaded([]) state is not equal to coldStart state")
    func emptyLoadedDistinguishableFromColdStart() {
        let emptyLoaded = SuggestionsState.loaded([])
        let coldStart = SuggestionsState.coldStart

        #expect(emptyLoaded != coldStart,
                "An empty loaded result is distinct from cold start")
    }

    @Test("loaded([]) state is not equal to loading state")
    func emptyLoadedDistinguishableFromLoading() {
        let emptyLoaded = SuggestionsState.loaded([])
        let loading = SuggestionsState.loading

        #expect(emptyLoaded != loading)
    }

    @Test("All four SuggestionsState cases are distinct")
    func allStatesDistinct() {
        let states: [SuggestionsState] = [
            .idle,
            .loading,
            .coldStart,
            .loaded([]),
        ]

        for i in states.indices {
            for j in states.indices where i != j {
                #expect(states[i] != states[j],
                        "State \(i) and state \(j) must be distinct")
            }
        }
    }

    // MARK: - Cold start resolves after first songs

    @Test("Non-empty history strategy produces results (cold start resolved)")
    func coldStartResolvesWithHistory() async {
        struct HistoryProvider: RecommendationProvider {
            let identifier: StrategyID = "history"
            let isAvailable: Bool = true
            func candidates(for songID: SuggestionSongID,
                            limit: Int) async throws(RecommendationError) -> [Suggestion] {
                [
                    Suggestion(songID: "historySong1", strategy: .history, score: 0.8),
                    Suggestion(songID: "historySong2", strategy: .history, score: 0.6),
                ]
            }
        }

        let engine = BlendedRecommendationEngine(
            providers: [
                UnavailableProvider(identifier: "sameChannel"),
                EmptyProvider(identifier: "coOccurrence"),
                HistoryProvider(),
                EmptyProvider(identifier: "favourite"),
            ],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "anySong0001",
            excluding: [],
            limit: 10
        )

        #expect(!results.isEmpty, "History data resolves cold start")
        #expect(results.count == 2)
    }
}
