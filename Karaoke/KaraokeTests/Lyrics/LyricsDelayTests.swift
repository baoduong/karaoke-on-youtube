// T087 — LyricsDelayTests.
//
// Asserts that with a non-zero route delay, the lookup returns the line and
// word that will be HEARD at that moment, not the one being dispatched.
// Tested against a table of delay values including zero.
//
// This is the test that catches the most consequential omission: if
// outputLatencyMs is not subtracted, the words run ahead of the sound.
// Because Bluetooth is the only supported route, this is wrong for every song.
//
// Satisfies: contracts/lyrics-provider.md Test contract (Route-delay compensation)

import Testing
import Foundation
@testable import Karaoke

@Suite("LyricsDelay")
struct LyricsDelayTests {

    // Synthetic track: lines at 0, 2, 4, 6, 8 seconds.
    // Each line is 2 seconds long.
    let track = LyricsTrackData(
        songID: "delay-test",
        source: .lrclib,
        hasWordTiming: true,
        globalOffsetMs: 0,
        fetchedAt: Date(),
        lines: [
            LyricsLineData(
                index: 0,
                startMs: 0,
                endMs: 2_000,
                text: "alpha",
                words: [LyricsWordData(lineIndex: 0, index: 0, startMs: 0, text: "alpha")]
            ),
            LyricsLineData(
                index: 1,
                startMs: 2_000,
                endMs: 4_000,
                text: "bravo",
                words: [LyricsWordData(lineIndex: 1, index: 0, startMs: 2_000, text: "bravo")]
            ),
            LyricsLineData(
                index: 2,
                startMs: 4_000,
                endMs: 6_000,
                text: "charlie",
                words: [LyricsWordData(lineIndex: 2, index: 0, startMs: 4_000, text: "charlie")]
            ),
            LyricsLineData(
                index: 3,
                startMs: 6_000,
                endMs: 8_000,
                text: "delta",
                words: [LyricsWordData(lineIndex: 3, index: 0, startMs: 6_000, text: "delta")]
            ),
            LyricsLineData(
                index: 4,
                startMs: 8_000,
                endMs: 10_000,
                text: "echo",
                words: [LyricsWordData(lineIndex: 4, index: 0, startMs: 8_000, text: "echo")]
            )
        ]
    )

    var timeline: LyricsTimeline { LyricsTimeline(track: track) }

    // MARK: Zero delay (baseline)

    @Test("Zero delay: dispatched position equals heard position")
    func zeroDelay() {
        // At 3.0s dispatched, 0ms delay → heard at 3.0s → line 1 (bravo, 2s–4s)
        let pos = timeline.position(
            atPositionSeconds: 3.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 1)
    }

    // MARK: Delay table

    struct DelayCase {
        let dispatchedSeconds: Double
        let outputLatencyMs: Double
        let expectedLineIndex: Int?
        let description: String
    }

    @Test("Delay table: lookup returns the line heard, not dispatched")
    func delayTable() {
        // The formula: effectiveMs = dispatchedMs - outputLatencyMs
        // So if dispatched=3000ms and delay=1000ms, effective=2000ms → line 1 boundary.
        let cases: [DelayCase] = [
            // Zero delay — dispatched == heard
            DelayCase(dispatchedSeconds: 3.0, outputLatencyMs: 0,   expectedLineIndex: 1, description: "0ms delay at 3s"),
            // 200ms Bluetooth delay (typical)
            // Dispatched 3.0s = 3000ms, delay 200ms → effective 2800ms → line 1
            DelayCase(dispatchedSeconds: 3.0, outputLatencyMs: 200, expectedLineIndex: 1, description: "200ms delay at 3s"),
            // 200ms delay shifts the boundary: dispatched 2.2s → effective 2000ms → line 1 boundary
            DelayCase(dispatchedSeconds: 2.2, outputLatencyMs: 200, expectedLineIndex: 1, description: "200ms delay at 2.2s"),
            // Without delay subtraction, 2.2s would be in line 1 (2s–4s).
            // With 200ms delay, effective = 2000ms → still line 1 (boundary).
            // Now test a case where delay changes the line:
            // Dispatched 2.1s = 2100ms, delay 200ms → effective 1900ms → line 0 (0–2000ms)
            DelayCase(dispatchedSeconds: 2.1, outputLatencyMs: 200, expectedLineIndex: 0, description: "200ms delay shifts line at 2.1s"),
            // 500ms delay
            // Dispatched 4.6s = 4600ms, delay 500ms → effective 4100ms → line 2 (4s–6s)
            DelayCase(dispatchedSeconds: 4.6, outputLatencyMs: 500, expectedLineIndex: 2, description: "500ms delay at 4.6s"),
            // Without delay: 4.6s → line 2. With 500ms: effective 4100ms → still line 2. Same result here.
            // Test where delay changes the line:
            // Dispatched 4.4s = 4400ms, delay 500ms → effective 3900ms → line 1 (2s–4s)
            DelayCase(dispatchedSeconds: 4.4, outputLatencyMs: 500, expectedLineIndex: 1, description: "500ms delay shifts line at 4.4s"),
            // Large delay: 1000ms
            // Dispatched 3.0s = 3000ms, delay 1000ms → effective 2000ms → line 1 boundary
            DelayCase(dispatchedSeconds: 3.0, outputLatencyMs: 1_000, expectedLineIndex: 1, description: "1000ms delay at 3s"),
            // Dispatched 2.9s = 2900ms, delay 1000ms → effective 1900ms → line 0
            DelayCase(dispatchedSeconds: 2.9, outputLatencyMs: 1_000, expectedLineIndex: 0, description: "1000ms delay shifts line at 2.9s")
        ]

        for c in cases {
            let pos = timeline.position(
                atPositionSeconds: c.dispatchedSeconds,
                outputLatencyMs: c.outputLatencyMs,
                globalOffsetMs: 0,
                manualLyricsOffsetMs: 0
            )
            #expect(pos.lineIndex == c.expectedLineIndex, "\(c.description): expected line \(String(describing: c.expectedLineIndex)), got \(String(describing: pos.lineIndex))")
        }
    }

    @Test("Delay subtraction: dispatched at line boundary minus delay lands in previous line")
    func delaySubtractionAtBoundary() {
        // Line 2 starts at 4000ms. Dispatched at exactly 4.0s with 200ms delay:
        // effective = 4000 - 200 = 3800ms → line 1 (2s–4s), not line 2.
        let pos = timeline.position(
            atPositionSeconds: 4.0,
            outputLatencyMs: 200,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 1)
    }

    @Test("Without delay subtraction, words would run ahead of sound")
    func withoutDelaySubtractionWordsRunAhead() {
        // This test proves the formula is correct by showing what happens
        // when delay is correctly applied vs incorrectly ignored.
        //
        // Scenario: Bluetooth delay is 200ms.
        // The room hears what was dispatched 200ms ago.
        // At dispatch time 4.2s, the room is hearing what was dispatched at 4.0s.
        // Effective time = 4200 - 200 = 4000ms → line 2 boundary.
        //
        // If we IGNORED the delay (wrong): 4200ms → line 2.
        // If we APPLY the delay (correct): 4000ms → line 2 boundary.
        // Both happen to be line 2 here. Let's use a clearer case:
        //
        // Dispatched 4.1s = 4100ms, delay 200ms → effective 3900ms → line 1.
        // Without delay: 4100ms → line 2. WRONG.
        // With delay: 3900ms → line 1. CORRECT (room is still hearing line 1).

        let withDelay = timeline.position(
            atPositionSeconds: 4.1,
            outputLatencyMs: 200,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        let withoutDelay = timeline.position(
            atPositionSeconds: 4.1,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )

        // With correct delay: room is hearing line 1 (bravo)
        #expect(withDelay.lineIndex == 1)
        // Without delay: would show line 2 (charlie) — ahead of what the room hears
        #expect(withoutDelay.lineIndex == 2)
        // The two must differ — this is the test that catches the omission.
        #expect(withDelay.lineIndex != withoutDelay.lineIndex)
    }
}
