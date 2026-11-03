// T103 — Deduplication and attribution tests.
//
// A song produced by three strategies appears once, attributed to the
// highest-priority one (recommendation-provider.md Blending step 2).

import Foundation
import Testing
@testable import Karaoke

@Suite("Blending — Deduplication and Attribution")
struct BlendingTests {

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

    // MARK: - Deduplication

    @Test("Song produced by multiple strategies appears exactly once")
    func deduplicatedToOne() async {
        // "sharedSong1" appears in all three strategies.
        let sameChannel = FixedProvider(
            identifier: "sameChannel",
            fixed: [Suggestion(songID: "sharedSong1", strategy: .sameChannel, score: 0.8)]
        )
        let coOccurrence = FixedProvider(
            identifier: "coOccurrence",
            fixed: [Suggestion(songID: "sharedSong1", strategy: .coOccurrence, score: 0.7)]
        )
        let history = FixedProvider(
            identifier: "history",
            fixed: [Suggestion(songID: "sharedSong1", strategy: .history, score: 0.6)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [sameChannel, coOccurrence, history],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let matching = results.filter { $0.songID == "sharedSong1" }
        #expect(matching.count == 1, "Shared song must appear exactly once, got \(matching.count)")
    }

    @Test("Deduplicated song is attributed to the highest-priority strategy")
    func attributedToHighestPriority() async {
        // sameChannel (priority 1) < coOccurrence (priority 2) < history (priority 3)
        // So sameChannel wins.
        let sameChannel = FixedProvider(
            identifier: "sameChannel",
            fixed: [Suggestion(songID: "sharedSong1", strategy: .sameChannel, score: 0.5)]
        )
        let coOccurrence = FixedProvider(
            identifier: "coOccurrence",
            fixed: [Suggestion(songID: "sharedSong1", strategy: .coOccurrence, score: 0.9)]
        )
        let history = FixedProvider(
            identifier: "history",
            fixed: [Suggestion(songID: "sharedSong1", strategy: .history, score: 0.8)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [sameChannel, coOccurrence, history],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let match = results.first { $0.songID == "sharedSong1" }
        #expect(match != nil)
        // sameChannel has lower rawValue (1) than coOccurrence (2) and history (3),
        // so it is the highest-priority strategy.
        #expect(match?.strategy == .sameChannel,
                "Expected sameChannel attribution, got \(String(describing: match?.strategy))")
    }

    @Test("Song from three strategies: attribution is highest-priority, not highest-score")
    func attributionByPriorityNotScore() async {
        // history has the highest score but lowest priority.
        // coOccurrence has medium score and medium priority.
        // sameChannel has the lowest score but highest priority.
        // Result: sameChannel wins attribution.
        let sameChannel = FixedProvider(
            identifier: "sameChannel",
            fixed: [Suggestion(songID: "contestedID1", strategy: .sameChannel, score: 0.1)]
        )
        let coOccurrence = FixedProvider(
            identifier: "coOccurrence",
            fixed: [Suggestion(songID: "contestedID1", strategy: .coOccurrence, score: 0.5)]
        )
        let history = FixedProvider(
            identifier: "history",
            fixed: [Suggestion(songID: "contestedID1", strategy: .history, score: 1.0)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [sameChannel, coOccurrence, history],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let match = results.first { $0.songID == "contestedID1" }
        #expect(match?.strategy == .sameChannel,
                "Priority beats score for attribution: expected sameChannel")
    }

    @Test("Unique songs from each strategy all appear")
    func uniqueSongsAllAppear() async {
        let sameChannel = FixedProvider(
            identifier: "sameChannel",
            fixed: [Suggestion(songID: "channelSong1", strategy: .sameChannel, score: 0.8)]
        )
        let history = FixedProvider(
            identifier: "history",
            fixed: [Suggestion(songID: "historySong1", strategy: .history, score: 0.7)]
        )
        let favourite = FixedProvider(
            identifier: "favourite",
            fixed: [Suggestion(songID: "favSong0001", strategy: .favourite, score: 0.6)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [sameChannel, history, favourite],
            deadline: 5.0
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let ids = results.map { $0.songID }
        #expect(ids.contains("channelSong1"))
        #expect(ids.contains("historySong1"))
        #expect(ids.contains("favSong0001"))
    }

    @Test("No duplicate songIDs in result list")
    func noDuplicateSongIDs() async {
        // Both providers return the same song plus unique ones.
        let p1 = FixedProvider(
            identifier: "sameChannel",
            fixed: [
                Suggestion(songID: "sharedSong1", strategy: .sameChannel, score: 0.9),
                Suggestion(songID: "uniqueSong11", strategy: .sameChannel, score: 0.5),
            ]
        )
        let p2 = FixedProvider(
            identifier: "history",
            fixed: [
                Suggestion(songID: "sharedSong1", strategy: .history, score: 0.8),
                Suggestion(songID: "uniqueSong22", strategy: .history, score: 0.4),
            ]
        )

        let engine = BlendedRecommendationEngine(providers: [p1, p2], deadline: 5.0)
        let results = await engine.suggestions(
            for: "currentSong1",
            context: ExclusionContext(currentSongID: "currentSong1"),
            limit: 10
        )

        let ids = results.map { $0.songID }
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count, "Result must contain no duplicate songIDs")
    }
}
