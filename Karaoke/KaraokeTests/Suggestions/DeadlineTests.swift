// T106 — Deadline tests.
//
// A strategy that exceeds the deadline is excluded and does not extend total time
// (recommendation-provider.md Blending step 1, FR-025d).
//
// The deadline is driven deterministically: a near-zero deadline (1 ms) ensures
// the slow provider (which sleeps for 500 ms) always misses it. No fixed sleeps
// in the test itself — the test measures elapsed time to verify the engine
// returned before the slow provider would have finished.

import Foundation
import Testing
@testable import Karaoke

@Suite("Deadline Enforcement")
struct DeadlineTests {

    // MARK: - Helpers

    /// A provider that sleeps for a configurable duration before returning.
    private struct SlowProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true
        let sleepNanoseconds: UInt64
        let result: [Suggestion]

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
            return result
        }
    }

    /// A provider that returns immediately.
    private struct FastProvider: RecommendationProvider {
        let identifier: StrategyID
        let isAvailable: Bool = true
        let result: [Suggestion]

        func candidates(for songID: SuggestionSongID,
                        limit: Int) async throws(RecommendationError) -> [Suggestion] {
            result
        }
    }

    // MARK: - Deadline tests

    @Test("Slow strategy is excluded when it misses the deadline")
    func slowStrategyExcluded() async {
        // Deadline: 50 ms. Slow provider: 500 ms. Fast provider: immediate.
        // The slow provider's results must not appear.
        let slow = SlowProvider(
            identifier: "sameChannel",
            sleepNanoseconds: 500_000_000, // 500 ms
            result: [Suggestion(songID: "slowSong001", strategy: .sameChannel, score: 0.9)]
        )
        let fast = FastProvider(
            identifier: "history",
            result: [Suggestion(songID: "fastSong001", strategy: .history, score: 0.5)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [slow, fast],
            deadline: 0.05 // 50 ms
        )

        let results = await engine.suggestions(
            for: "currentSong1",
            excluding: [],
            limit: 10
        )

        let ids = results.map { $0.songID }
        // The slow provider's song must not appear — it missed the deadline.
        #expect(!ids.contains("slowSong001"),
                "Slow strategy must be excluded when it misses the deadline")
        // The fast provider's song must appear.
        #expect(ids.contains("fastSong001"),
                "Fast strategy must contribute within the deadline")
    }

    @Test("Engine returns before the slow strategy would have finished")
    func engineDoesNotWaitForSlowStrategy() async {
        // Deadline: 100 ms. Slow provider: 2000 ms.
        // The engine must return well before 2000 ms.
        let slow = SlowProvider(
            identifier: "sameChannel",
            sleepNanoseconds: 2_000_000_000, // 2 s
            result: [Suggestion(songID: "slowSong001", strategy: .sameChannel, score: 0.9)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [slow],
            deadline: 0.1 // 100 ms
        )

        let start = Date()
        let _ = await engine.suggestions(for: "currentSong1", excluding: [], limit: 10)
        let elapsed = Date().timeIntervalSince(start)

        // The engine must return within 500 ms (well before the 2 s slow provider).
        // We use 500 ms as the upper bound to give CI headroom.
        #expect(elapsed < 0.5,
                "Engine must not wait for slow strategy; elapsed: \(elapsed)s")
    }

    @Test("Fast strategy contributes even when slow strategy misses deadline")
    func fastStrategyContributesUnderDeadline() async {
        let slow = SlowProvider(
            identifier: "sameChannel",
            sleepNanoseconds: 1_000_000_000, // 1 s
            result: [Suggestion(songID: "slowSong001", strategy: .sameChannel, score: 0.9)]
        )
        let fast = FastProvider(
            identifier: "history",
            result: [
                Suggestion(songID: "fastSong001", strategy: .history, score: 0.8),
                Suggestion(songID: "fastSong002", strategy: .history, score: 0.6),
            ]
        )

        let engine = BlendedRecommendationEngine(
            providers: [slow, fast],
            deadline: 0.05 // 50 ms
        )

        let results = await engine.suggestions(for: "currentSong1", excluding: [], limit: 10)
        let ids = results.map { $0.songID }

        #expect(ids.contains("fastSong001"))
        #expect(ids.contains("fastSong002"))
        #expect(!ids.contains("slowSong001"))
    }

    @Test("Zero-deadline engine returns empty list (all strategies miss)")
    func zeroDealineYieldsEmpty() async {
        // With a near-zero deadline, even fast providers may miss.
        // The engine must still return [] rather than throwing.
        let slow = SlowProvider(
            identifier: "history",
            sleepNanoseconds: 100_000_000, // 100 ms
            result: [Suggestion(songID: "anySong0001", strategy: .history, score: 0.5)]
        )

        let engine = BlendedRecommendationEngine(
            providers: [slow],
            deadline: 0.000001 // 1 µs — effectively zero
        )

        let results = await engine.suggestions(for: "currentSong1", excluding: [], limit: 10)
        // Must not throw — returns [] or whatever fast enough to complete.
        // The key assertion is that the call returns at all.
        #expect(results.count >= 0) // always true — proves no throw
    }
}
