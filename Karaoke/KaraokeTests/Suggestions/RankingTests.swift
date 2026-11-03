// T104 — Ranking determinism tests.
//
// Ordering follows strategy priority first, then score descending within a
// strategy, deterministically for a fixed input (recommendation-provider.md
// Blending step 4).

import Foundation
import Testing
@testable import Karaoke

@Suite("Ranking Determinism")
struct RankingTests {

    // MARK: - Helpers

    private struct FixedProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true
        let fixed: [Suggestion]

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            fixed
        }
    }

    // MARK: - Strategy priority ordering

    @Test("Strategy priority: sameChannel before coOccurrence before history before favourite")
    func strategyPriorityOrder() async {
        let p1 = FixedProvider(
            identifier: "sameChannel",
            fixed: [Suggestion(songID: "channelSong1", strategy: .sameChannel, score: 0.1)]
        )
        let p2 = FixedProvider(
            identifier: "coOccurrence",
            fixed: [Suggestion(songID: "coOccurSong1", strategy: .coOccurrence, score: 0.9)]
        )
        let p3 = FixedProvider(
            identifier: "history",
            fixed: [Suggestion(songID: "historySong1", strategy: .history, score: 0.8)]
        )
        let p4 = FixedProvider(
            identifier: "favourite",
            fixed: [Suggestion(songID: "favSong0001", strategy: .favourite, score: 0.7)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [p1, p2, p3, p4],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        // Strategy priority wins over score.
        // sameChannel (score 0.1) must come before coOccurrence (score 0.9).
        let ids = results.map { $0.songID }
        let channelIdx = ids.firstIndex(of: "channelSong1")
        let coOccurIdx = ids.firstIndex(of: "coOccurSong1")
        let historyIdx = ids.firstIndex(of: "historySong1")
        let favIdx = ids.firstIndex(of: "favSong0001")

        #expect(channelIdx != nil && coOccurIdx != nil && historyIdx != nil && favIdx != nil)
        if let c = channelIdx, let co = coOccurIdx, let h = historyIdx, let f = favIdx {
            #expect(c < co, "sameChannel must precede coOccurrence")
            #expect(co < h, "coOccurrence must precede history")
            #expect(h < f, "history must precede favourite")
        }
    }

    @Test("Within same strategy, higher score ranks first")
    func scoreOrderWithinStrategy() async {
        let provider = FixedProvider(
            identifier: "history",
            fixed: [
                Suggestion(songID: "lowScore001", strategy: .history, score: 0.2),
                Suggestion(songID: "highScore01", strategy: .history, score: 0.9),
                Suggestion(songID: "midScore001", strategy: .history, score: 0.5),
            ]
        )

        let engine = BlendedRecommendationEngine(providers: [provider], deadline: 5.0)
        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let ids = results.map { $0.songID }
        let highIdx = ids.firstIndex(of: "highScore01")
        let midIdx = ids.firstIndex(of: "midScore001")
        let lowIdx = ids.firstIndex(of: "lowScore001")

        #expect(highIdx != nil && midIdx != nil && lowIdx != nil)
        if let h = highIdx, let m = midIdx, let l = lowIdx {
            #expect(h < m, "Higher score must rank before mid score")
            #expect(m < l, "Mid score must rank before lower score")
        }
    }

    @Test("Ranking is deterministic for identical inputs")
    func rankingIsDeterministic() async {
        let suggestions = [
            Suggestion(songID: "song0000001", strategy: .history, score: 0.7),
            Suggestion(songID: "song0000002", strategy: .history, score: 0.5),
            Suggestion(songID: "song0000003", strategy: .coOccurrence, score: 0.9),
        ]

        let provider = FixedProvider(identifier: "history", fixed: suggestions)
        let engine = BlendedRecommendationEngine(providers: [provider], deadline: 5.0)

        let context = ExclusionContext(currentSongID: "currentSong1")

        let results1 = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let results2 = await engine.suggestions(for: "currentSong1", context: context, limit: 10)

        #expect(results1.map { $0.songID } == results2.map { $0.songID },
                "Ranking must be deterministic for identical inputs")
    }

    @Test("Tie-break by songID is deterministic")
    func tieBreakBySongID() async {
        // Two songs with identical strategy and score — tie-break by songID.
        let provider = FixedProvider(
            identifier: "history",
            fixed: [
                Suggestion(songID: "zzz0000001", strategy: .history, score: 0.5),
                Suggestion(songID: "aaa0000001", strategy: .history, score: 0.5),
            ]
        )

        let engine = BlendedRecommendationEngine(providers: [provider], deadline: 5.0)
        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let ids = results.map { $0.songID }
        // "aaa0000001" < "zzz0000001" lexicographically.
        let aaaIdx = ids.firstIndex(of: "aaa0000001")
        let zzzIdx = ids.firstIndex(of: "zzz0000001")

        #expect(aaaIdx != nil && zzzIdx != nil)
        if let a = aaaIdx, let z = zzzIdx {
            #expect(a < z, "Tie-break by songID must be deterministic (lexicographic)")
        }
    }

    @Test("Limit truncates results to requested count")
    func limitTruncates() async {
        let provider = FixedProvider(
            identifier: "history",
            fixed: (1...20).map { i in
                Suggestion(
                    songID: String(format: "song%07d", i),
                    strategy: .history,
                    score: Double(i) / 20.0
                )
            }
        )

        let engine = BlendedRecommendationEngine(providers: [provider], deadline: 5.0)
        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 5
        )

        #expect(results.count == 5, "Result must be truncated to the requested limit")
    }
}
