// T085 — LyricsTimelineTests.
//
// Lookup at boundary times: before the first line, exactly on a boundary,
// mid-word, in a gap, and after the last line.
//
// Satisfies: contracts/lyrics-provider.md Test contract (Lookup)

import Testing
import Foundation
@testable import Karaoke

@Suite("LyricsTimeline")
struct LyricsTimelineTests {

    // Synthetic track:
    //   Line 0: 1000ms–5000ms  "alpha bravo"
    //     Word 0: 1000ms "alpha"
    //     Word 1: 2500ms "bravo"
    //   Line 1: 5000ms–9000ms  "charlie delta"  (no words)
    //   Line 2: 9000ms–12000ms "echo"
    //     Word 0: 9000ms "echo"
    let track = LyricsTrackData(
        songID: "test",
        source: .lrclib,
        hasWordTiming: true,
        globalOffsetMs: 0,
        fetchedAt: Date(),
        lines: [
            LyricsLineData(
                index: 0,
                startMs: 1_000,
                endMs: 5_000,
                text: "alpha bravo",
                words: [
                    LyricsWordData(lineIndex: 0, index: 0, startMs: 1_000, text: "alpha"),
                    LyricsWordData(lineIndex: 0, index: 1, startMs: 2_500, text: "bravo")
                ]
            ),
            LyricsLineData(
                index: 1,
                startMs: 5_000,
                endMs: 9_000,
                text: "charlie delta",
                words: []
            ),
            LyricsLineData(
                index: 2,
                startMs: 9_000,
                endMs: 12_000,
                text: "echo",
                words: [
                    LyricsWordData(lineIndex: 2, index: 0, startMs: 9_000, text: "echo")
                ]
            )
        ]
    )

    var timeline: LyricsTimeline { LyricsTimeline(track: track) }

    // MARK: Before the first line

    @Test("Returns nil lineIndex before the first line")
    func beforeFirstLine() {
        let pos = timeline.position(
            atPositionSeconds: 0.5,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == nil)
        #expect(pos.wordIndex == nil)
    }

    // MARK: Exactly on a boundary

    @Test("Returns correct line exactly on the first line's start boundary")
    func exactlyOnFirstLineBoundary() {
        let pos = timeline.position(
            atPositionSeconds: 1.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 0)
    }

    @Test("Returns correct line exactly on the second line's start boundary")
    func exactlyOnSecondLineBoundary() {
        let pos = timeline.position(
            atPositionSeconds: 5.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 1)
    }

    // MARK: Mid-word

    @Test("Returns correct word index mid-word")
    func midWord() {
        // At 2.0s: line 0, word 0 ("alpha" starts at 1.0s, word 1 starts at 2.5s)
        let pos = timeline.position(
            atPositionSeconds: 2.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 0)
        #expect(pos.wordIndex == 0)
        // Progress: (2000 - 1000) / (2500 - 1000) = 1000/1500 ≈ 0.667
        let expectedProgress = 1000.0 / 1500.0
        #expect(abs((pos.progressWithinWord) - expectedProgress) < 0.001)
    }

    @Test("Returns correct word index at second word start")
    func atSecondWordStart() {
        let pos = timeline.position(
            atPositionSeconds: 2.5,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 0)
        #expect(pos.wordIndex == 1)
    }

    // MARK: In a gap (line with no words)

    @Test("Returns correct line in a gap (line with no word timing)")
    func inGapLine() {
        let pos = timeline.position(
            atPositionSeconds: 7.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 1)
        #expect(pos.wordIndex == nil)
    }

    // MARK: After the last line

    @Test("Returns nil lineIndex after the last line ends")
    func afterLastLine() {
        let pos = timeline.position(
            atPositionSeconds: 13.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == nil)
    }

    // MARK: Empty track

    @Test("Returns nil for an empty track")
    func emptyTrack() {
        let emptyTrack = LyricsTrackData(
            songID: "empty",
            source: .lrclib,
            hasWordTiming: false,
            globalOffsetMs: 0,
            fetchedAt: Date(),
            lines: []
        )
        let tl = LyricsTimeline(track: emptyTrack)
        let pos = tl.position(
            atPositionSeconds: 5.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == nil)
        #expect(pos.wordIndex == nil)
    }
}
