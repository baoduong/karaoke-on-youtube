// T107 — Local-only guarantee tests.
//
// With upstream strategies disabled and a populated store, the result is still
// non-empty (recommendation-provider.md Test contract: Local-only guarantee).
//
// This is the guarantee behind FR-025b: for any singer who has used the app for
// more than a few songs, the list is never empty even with no network at all.

import Foundation
import Testing
@testable import Karaoke

@Suite("Local-Only Guarantee")
struct LocalOnlyTests {

    // MARK: - Helpers

    private struct LocalOnlyProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true
        let fixed: [Suggestion]

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            fixed
        }
    }

    private struct UpstreamProvider: RecommendationProvider {
        let identifier: StrategyID = "sameChannel"
        let isAvailable: Bool = false // disabled

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            throw RecommendationError.strategyUnavailable
        }
    }

    // MARK: - Tests

    @Test("Local strategies produce results when upstream is disabled")
    func localStrategiesWorkWithoutUpstream() async {
        let upstream = UpstreamProvider()
        let history = LocalOnlyProvider(
            identifier: "history",
            fixed: [
                Suggestion(songID: "historySong1", strategy: .history, score: 0.8),
                Suggestion(songID: "historySong2", strategy: .history, score: 0.6),
            ]
        )

        let engine = BlendedRecommendationEngine(
            providers: [upstream, history],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            excluding: [],
            limit: 10
        )

        #expect(!results.isEmpty, "Local strategies must produce results even when upstream is disabled")
        #expect(results.allSatisfy { $0.strategy != .sameChannel },
                "No upstream results must appear when upstream is disabled")
    }

    @Test("coOccurrence strategy contributes without network")
    func coOccurrenceContributesOffline() async {
        let coOccurrence = LocalOnlyProvider(
            identifier: "coOccurrence",
            fixed: [
                Suggestion(songID: "coSong00001", strategy: .coOccurrence, score: 0.9),
                Suggestion(songID: "coSong00002", strategy: .coOccurrence, score: 0.7),
            ]
        )

        let engine = BlendedRecommendationEngine(
            providers: [coOccurrence],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            excluding: [],
            limit: 10
        )

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.strategy == .coOccurrence })
    }

    @Test("favourite strategy contributes without network")
    func favouriteContributesOffline() async {
        let favourite = LocalOnlyProvider(
            identifier: "favourite",
            fixed: [
                Suggestion(songID: "favSong0001", strategy: .favourite, score: 1.0),
                Suggestion(songID: "favSong0002", strategy: .favourite, score: 0.8),
            ]
        )

        let engine = BlendedRecommendationEngine(
            providers: [favourite],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            excluding: [],
            limit: 10
        )

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.strategy == .favourite })
    }

    @Test("Multiple local strategies blend correctly without upstream")
    func multipleLocalStrategiesBlend() async {
        let coOccurrence = LocalOnlyProvider(
            identifier: "coOccurrence",
            fixed: [Suggestion(songID: "coSong00001", strategy: .coOccurrence, score: 0.9)]
        )
        let history = LocalOnlyProvider(
            identifier: "history",
            fixed: [Suggestion(songID: "historySong1", strategy: .history, score: 0.7)]
        )
        let favourite = LocalOnlyProvider(
            identifier: "favourite",
            fixed: [Suggestion(songID: "favSong0001", strategy: .favourite, score: 0.5)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [coOccurrence, history, favourite],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            excluding: [],
            limit: 10
        )

        let ids = results.map { $0.songID }
        #expect(ids.contains("coSong00001"))
        #expect(ids.contains("historySong1"))
        #expect(ids.contains("favSong0001"))
        #expect(results.count == 3)
    }

    @Test("Local strategies respect exclusions even without upstream")
    func localStrategiesRespectExclusions() async {
        let history = LocalOnlyProvider(
            identifier: "history",
            fixed: [
                Suggestion(songID: "sungSong111", strategy: .history, score: 0.9),
                Suggestion(songID: "freshSong11", strategy: .history, score: 0.5),
            ]
        )

        let engine = BlendedRecommendationEngine(providers: [history], deadline: 5.0)

        let context = ExclusionContext(
            currentSongID: "currentSong1",
            performedSongIDs: ["sungSong111"]
        )

        let results = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("sungSong111"), "Exclusions must apply even in local-only mode")
        #expect(ids.contains("freshSong11"))
    }
}
