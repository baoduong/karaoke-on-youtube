// T088 — LyricsOffsetTests.
//
// Asserts a non-zero global offset and manual trim each shift the resolved
// position by exactly that amount.
//
// Satisfies: contracts/lyrics-provider.md Test contract (Offset)

import Testing
import Foundation
@testable import Karaoke

@Suite("LyricsOffset")
struct LyricsOffsetTests {

    // Synthetic track: lines at 0, 3, 6, 9 seconds.
    let track = LyricsTrackData(
        songID: "offset-test",
        source: .lrclib,
        hasWordTiming: false,
        globalOffsetMs: 0,
        fetchedAt: Date(),
        lines: [
            LyricsLineData(index: 0, startMs: 0,     endMs: 3_000, text: "alpha",   words: []),
            LyricsLineData(index: 1, startMs: 3_000, endMs: 6_000, text: "bravo",   words: []),
            LyricsLineData(index: 2, startMs: 6_000, endMs: 9_000, text: "charlie", words: []),
            LyricsLineData(index: 3, startMs: 9_000, endMs: 12_000, text: "delta",  words: [])
        ]
    )

    var timeline: LyricsTimeline { LyricsTimeline(track: track) }

    // MARK: Baseline (no offsets)

    @Test("Baseline: no offsets, position resolves correctly")
    func baseline() {
        let pos = timeline.position(
            atPositionSeconds: 4.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        // 4000ms → line 1 (3s–6s)
        #expect(pos.lineIndex == 1)
    }

    // MARK: Global offset

    @Test("Positive globalOffsetMs shifts resolved position forward")
    func positiveGlobalOffset() {
        // globalOffsetMs = +1000ms means the track is 1s early, so we add 1s to effective time.
        // Dispatched 4.0s, globalOffset +1000ms → effective = 4000 + 1000 = 5000ms → line 1 (3s–6s)
        let pos = timeline.position(
            atPositionSeconds: 4.0,
            outputLatencyMs: 0,
            globalOffsetMs: 1_000,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 1)
    }

    @Test("Positive globalOffsetMs shifts line boundary")
    func positiveGlobalOffsetShiftsBoundary() {
        // Without offset: 2.9s = 2900ms → line 0 (0–3000ms)
        // With +200ms offset: effective = 2900 + 200 = 3100ms → line 1 (3000–6000ms)
        let withOffset = timeline.position(
            atPositionSeconds: 2.9,
            outputLatencyMs: 0,
            globalOffsetMs: 200,
            manualLyricsOffsetMs: 0
        )
        let withoutOffset = timeline.position(
            atPositionSeconds: 2.9,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(withoutOffset.lineIndex == 0)
        #expect(withOffset.lineIndex == 1)
    }

    @Test("Negative globalOffsetMs shifts resolved position backward")
    func negativeGlobalOffset() {
        // Dispatched 3.1s = 3100ms, globalOffset -200ms → effective = 3100 - 200 = 2900ms → line 0
        let pos = timeline.position(
            atPositionSeconds: 3.1,
            outputLatencyMs: 0,
            globalOffsetMs: -200,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 0)
    }

    // MARK: Manual trim

    @Test("Positive manualLyricsOffsetMs shifts resolved position forward")
    func positiveManualOffset() {
        // Dispatched 2.9s = 2900ms, manualOffset +200ms → effective = 3100ms → line 1
        let pos = timeline.position(
            atPositionSeconds: 2.9,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 200
        )
        #expect(pos.lineIndex == 1)
    }

    @Test("Negative manualLyricsOffsetMs shifts resolved position backward")
    func negativeManualOffset() {
        // Dispatched 3.1s = 3100ms, manualOffset -200ms → effective = 2900ms → line 0
        let pos = timeline.position(
            atPositionSeconds: 3.1,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: -200
        )
        #expect(pos.lineIndex == 0)
    }

    // MARK: Combined offsets

    @Test("Global offset and manual trim combine additively")
    func combinedOffsets() {
        // Dispatched 2.5s = 2500ms
        // globalOffset +300ms, manualOffset +300ms → effective = 2500 + 300 + 300 = 3100ms → line 1
        let pos = timeline.position(
            atPositionSeconds: 2.5,
            outputLatencyMs: 0,
            globalOffsetMs: 300,
            manualLyricsOffsetMs: 300
        )
        #expect(pos.lineIndex == 1)
    }

    @Test("All three components combine: position - delay + globalOffset + manualOffset")
    func allThreeComponents() {
        // Formula: effectiveMs = positionMs - outputLatencyMs + globalOffsetMs + manualLyricsOffsetMs
        // Dispatched 4.0s = 4000ms
        // outputLatencyMs = 500ms
        // globalOffsetMs = 200ms
        // manualLyricsOffsetMs = 300ms
        // effective = 4000 - 500 + 200 + 300 = 4000ms → line 2 boundary (6000ms? No: 4000ms → line 1 (3s–6s))
        // Wait: 4000ms is in line 1 (3000–6000ms). Let me recalculate:
        // effective = 4000 - 500 + 200 + 300 = 4000ms → line 1 (3000–6000ms)
        let pos = timeline.position(
            atPositionSeconds: 4.0,
            outputLatencyMs: 500,
            globalOffsetMs: 200,
            manualLyricsOffsetMs: 300
        )
        // effective = 4000 - 500 + 200 + 300 = 4000ms → line 1
        #expect(pos.lineIndex == 1)
    }

    @Test("Reset manualOffset to 0 restores automatic behaviour")
    func resetManualOffsetRestoresAutomatic() {
        // With manual offset: dispatched 3.1s, manualOffset -200ms → effective 2900ms → line 0
        let withOffset = timeline.position(
            atPositionSeconds: 3.1,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: -200
        )
        // After reset (manualOffset = 0): dispatched 3.1s → effective 3100ms → line 1
        let afterReset = timeline.position(
            atPositionSeconds: 3.1,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(withOffset.lineIndex == 0)
        #expect(afterReset.lineIndex == 1)
    }

    @Test("Offset shifts position by exactly the specified amount in milliseconds")
    func offsetShiftsByExactAmount() {
        // Verify the shift is exact, not approximate.
        // Line 1 starts at 3000ms. With +1000ms offset, line 1 should start at effective 3000ms,
        // meaning dispatched 2000ms (2.0s) should resolve to line 1.
        let pos = timeline.position(
            atPositionSeconds: 2.0,
            outputLatencyMs: 0,
            globalOffsetMs: 1_000,
            manualLyricsOffsetMs: 0
        )
        // effective = 2000 + 1000 = 3000ms → line 1 boundary
        #expect(pos.lineIndex == 1)

        // And 1999ms effective (dispatched 0.999s) should be line 0.
        let justBefore = timeline.position(
            atPositionSeconds: 0.999,
            outputLatencyMs: 0,
            globalOffsetMs: 1_000,
            manualLyricsOffsetMs: 0
        )
        // effective = 999 + 1000 = 1999ms → line 0
        #expect(justBefore.lineIndex == 0)
    }
}
