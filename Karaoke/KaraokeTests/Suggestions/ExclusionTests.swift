// T102 — Exclusion rule tests.
//
// Tests all four exclusion rules, with the already-sung case tested explicitly
// because offering the song that just finished is the failure everyone notices
// immediately (recommendation-provider.md Exclusion rules).
//
// Rule 1: the currently playing song.
// Rule 2: every song in performedSongIDs (FR-025c) — THE VISIBLE FAILURE.
// Rule 3: songs already queued as waiting.
// Rule 4: songs whose last resolution failed with a content-side error.

import Foundation
import Testing
@testable import Karaoke

@Suite("Exclusion Rules")
struct ExclusionTests {

    // MARK: - Helpers

    /// A provider that returns a fixed list of suggestions.
    private struct FixedProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true
        let fixed: [Suggestion]

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            fixed
        }
    }

    private func makeEngine(suggestions: [Suggestion]) -> BlendedRecommendationEngine {
        BlendedRecommendationEngine(
            providers: [FixedProvider(identifier: "history", fixed: suggestions)],
            deadline: 5.0
        )
    }

    // MARK: - Rule 1: currently playing song

    @Test("Rule 1: currently playing song is excluded")
    func currentSongExcluded() async {
        let engine = makeEngine(suggestions: [
            Suggestion(songID: "currentSong1", strategy: .history, score: 0.9),
            Suggestion(songID: "otherSong11", strategy: .history, score: 0.5),
        ])

        let context = ExclusionContext(
            currentSongID: "currentSong1",
            performedSongIDs: [],
            waitingQueueSongIDs: [],
            contentFailedSongIDs: []
        )

        let results = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("currentSong1"), "Currently playing song must not appear in suggestions")
        #expect(ids.contains("otherSong11"))
    }

    // MARK: - Rule 2: already-sung songs (THE VISIBLE FAILURE)

    @Test("Rule 2: already-sung songs are excluded — the visible failure")
    func alreadySungExcluded() async {
        // This is the rule whose absence makes a suggestion list visibly stupid.
        // Offering the song that just finished is the failure everyone notices.
        let engine = makeEngine(suggestions: [
            Suggestion(songID: "sungSong111", strategy: .history, score: 0.9),
            Suggestion(songID: "sungSong222", strategy: .history, score: 0.8),
            Suggestion(songID: "freshSong11", strategy: .history, score: 0.7),
        ])

        let context = ExclusionContext(
            currentSongID: "nowPlaying1",
            performedSongIDs: ["sungSong111", "sungSong222"],
            waitingQueueSongIDs: [],
            contentFailedSongIDs: []
        )

        let results = await engine.suggestions(for: "nowPlaying1", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("sungSong111"), "Song sung earlier this session must not appear")
        #expect(!ids.contains("sungSong222"), "Song sung earlier this session must not appear")
        #expect(ids.contains("freshSong11"), "Unsung song must appear")
    }

    @Test("Rule 2: the song that just finished is excluded")
    func justFinishedSongExcluded() async {
        // Simulate: "nowPlaying1" just finished and is now in performedSongIDs.
        // The next song is "nextSong111". Suggestions must not include "nowPlaying1".
        let engine = makeEngine(suggestions: [
            Suggestion(songID: "nowPlaying1", strategy: .history, score: 0.95),
            Suggestion(songID: "nextSong111", strategy: .history, score: 0.6),
        ])

        let context = ExclusionContext(
            currentSongID: "nextSong111",
            performedSongIDs: ["nowPlaying1"], // just finished
            waitingQueueSongIDs: [],
            contentFailedSongIDs: []
        )

        let results = await engine.suggestions(for: "nextSong111", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("nowPlaying1"), "The song that just finished must not be suggested")
    }

    @Test("Rule 2: entire performed set is excluded")
    func entirePerformedSetExcluded() async {
        let performed: Set<String> = ["song0000001", "song0000002", "song0000003"]
        let engine = makeEngine(suggestions: performed.map {
            Suggestion(songID: $0, strategy: .history, score: 0.8)
        } + [Suggestion(songID: "freshSong11", strategy: .history, score: 0.5)])

        let context = ExclusionContext(
            currentSongID: "currentSong1",
            performedSongIDs: performed,
            waitingQueueSongIDs: [],
            contentFailedSongIDs: []
        )

        let results = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let ids = Set(results.map { $0.songID })

        for performedID in performed {
            #expect(!ids.contains(performedID), "Performed song \(performedID) must not appear")
        }
        #expect(ids.contains("freshSong11"))
    }

    // MARK: - Rule 3: already queued as waiting

    @Test("Rule 3: songs already queued as waiting are excluded")
    func waitingQueueExcluded() async {
        let engine = makeEngine(suggestions: [
            Suggestion(songID: "queuedSong1", strategy: .favourite, score: 0.9),
            Suggestion(songID: "notQueued11", strategy: .favourite, score: 0.5),
        ])

        let context = ExclusionContext(
            currentSongID: "currentSong1",
            performedSongIDs: [],
            waitingQueueSongIDs: ["queuedSong1"],
            contentFailedSongIDs: []
        )

        let results = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("queuedSong1"), "Already-queued song must not appear in suggestions")
        #expect(ids.contains("notQueued11"))
    }

    // MARK: - Rule 4: content-side resolution failures

    @Test("Rule 4: songs with content-side failures are excluded")
    func contentFailedExcluded() async {
        let engine = makeEngine(suggestions: [
            Suggestion(songID: "failedSong1", strategy: .sameChannel, score: 0.9),
            Suggestion(songID: "workingSong1", strategy: .sameChannel, score: 0.5),
        ])

        let context = ExclusionContext(
            currentSongID: "currentSong1",
            performedSongIDs: [],
            waitingQueueSongIDs: [],
            contentFailedSongIDs: ["failedSong1"]
        )

        let results = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("failedSong1"), "Content-failed song must not appear in suggestions")
        #expect(ids.contains("workingSong1"))
    }

    // MARK: - All four rules together

    @Test("All four exclusion rules applied simultaneously")
    func allRulesApplied() async {
        let engine = makeEngine(suggestions: [
            Suggestion(songID: "currentSong1", strategy: .history, score: 1.0), // rule 1
            Suggestion(songID: "sungSong111", strategy: .history, score: 0.9),  // rule 2
            Suggestion(songID: "queuedSong1", strategy: .history, score: 0.8),  // rule 3
            Suggestion(songID: "failedSong1", strategy: .history, score: 0.7),  // rule 4
            Suggestion(songID: "validSong11", strategy: .history, score: 0.6),  // should appear
        ])

        let context = ExclusionContext(
            currentSongID: "currentSong1",
            performedSongIDs: ["sungSong111"],
            waitingQueueSongIDs: ["queuedSong1"],
            contentFailedSongIDs: ["failedSong1"]
        )

        let results = await engine.suggestions(for: "currentSong1", context: context, limit: 10)
        let ids = results.map { $0.songID }

        #expect(!ids.contains("currentSong1"))
        #expect(!ids.contains("sungSong111"))
        #expect(!ids.contains("queuedSong1"))
        #expect(!ids.contains("failedSong1"))
        #expect(ids.contains("validSong11"))
        #expect(results.count == 1)
    }

    // MARK: - ExclusionContext unit tests

    @Test("ExclusionContext.shouldExclude: current song")
    func exclusionContextCurrentSong() {
        let ctx = ExclusionContext(currentSongID: "abc12345678")
        #expect(ctx.shouldExclude("abc12345678"))
        #expect(!ctx.shouldExclude("xyz12345678"))
    }

    @Test("ExclusionContext.shouldExclude: performed set")
    func exclusionContextPerformed() {
        let ctx = ExclusionContext(performedSongIDs: ["song0000001", "song0000002"])
        #expect(ctx.shouldExclude("song0000001"))
        #expect(ctx.shouldExclude("song0000002"))
        #expect(!ctx.shouldExclude("song0000003"))
    }

    @Test("ExclusionContext.shouldExclude: waiting queue")
    func exclusionContextWaiting() {
        let ctx = ExclusionContext(waitingQueueSongIDs: ["queued00001"])
        #expect(ctx.shouldExclude("queued00001"))
        #expect(!ctx.shouldExclude("notqueued01"))
    }

    @Test("ExclusionContext.shouldExclude: content failed")
    func exclusionContextContentFailed() {
        let ctx = ExclusionContext(contentFailedSongIDs: ["failed00001"])
        #expect(ctx.shouldExclude("failed00001"))
        #expect(!ctx.shouldExclude("working0001"))
    }
}
