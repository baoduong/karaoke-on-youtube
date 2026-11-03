// T086 — LyricsSeekTests.
//
// Asserts a jump to an arbitrary position returns the correct index on the
// FIRST lookup with no intermediate wrong value.
//
// Satisfies: contracts/lyrics-provider.md Test contract (Seek correction)

import Testing
import Foundation
@testable import Karaoke

@Suite("LyricsSeek")
struct LyricsSeekTests {

    // Synthetic track with 5 lines spread across 60 seconds.
    let track = LyricsTrackData(
        songID: "seek-test",
        source: .lrclib,
        hasWordTiming: false,
        globalOffsetMs: 0,
        fetchedAt: Date(),
        lines: [
            LyricsLineData(index: 0, startMs: 2_000,  endMs: 10_000, text: "alpha",   words: []),
            LyricsLineData(index: 1, startMs: 10_000, endMs: 20_000, text: "bravo",   words: []),
            LyricsLineData(index: 2, startMs: 20_000, endMs: 35_000, text: "charlie", words: []),
            LyricsLineData(index: 3, startMs: 35_000, endMs: 50_000, text: "delta",   words: []),
            LyricsLineData(index: 4, startMs: 50_000, endMs: 60_000, text: "echo",    words: [])
        ]
    )

    var timeline: LyricsTimeline { LyricsTimeline(track: track) }

    @Test("Seek to start of track returns nil (before first line)")
    func seekToStart() {
        let pos = timeline.position(
            atPositionSeconds: 0.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == nil)
    }

    @Test("Seek to middle of track returns correct line on first lookup")
    func seekToMiddle() {
        // Jump directly to 25s — should land in line 2 (charlie, 20s–35s).
        let pos = timeline.position(
            atPositionSeconds: 25.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 2)
    }

    @Test("Seek to end of track returns correct line on first lookup")
    func seekToEnd() {
        let pos = timeline.position(
            atPositionSeconds: 55.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == 4)
    }

    @Test("Seek backward from line 4 to line 1 returns correct line immediately")
    func seekBackward() {
        let tl = LyricsTimeline(track: track)

        // First lookup at line 4.
        let first = tl.position(
            atPositionSeconds: 55.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0,
            hint: nil
        )
        #expect(first.lineIndex == 4)

        // Seek backward to line 1 — must return correct index on the FIRST lookup.
        let afterSeek = tl.position(
            atPositionSeconds: 15.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0,
            hint: first.lineIndex
        )
        #expect(afterSeek.lineIndex == 1)
    }

    @Test("Seek forward from line 0 to line 3 returns correct line immediately")
    func seekForward() {
        let tl = LyricsTimeline(track: track)

        let first = tl.position(
            atPositionSeconds: 5.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0,
            hint: nil
        )
        #expect(first.lineIndex == 0)

        let afterSeek = tl.position(
            atPositionSeconds: 40.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0,
            hint: first.lineIndex
        )
        #expect(afterSeek.lineIndex == 3)
    }

    @Test("Seek to a gap between lines returns nil")
    func seekToGapBetweenLines() {
        // Line 0 ends at 10s, line 1 starts at 10s — no gap here.
        // But before line 0 (0–2s) is a gap.
        let pos = timeline.position(
            atPositionSeconds: 1.0,
            outputLatencyMs: 0,
            globalOffsetMs: 0,
            manualLyricsOffsetMs: 0
        )
        #expect(pos.lineIndex == nil)
    }

    @Test("Multiple seeks in sequence all return correct indices")
    func multipleSeeks() {
        let tl = LyricsTimeline(track: track)
        var hint: Int? = nil

        let positions: [(Double, Int?)] = [
            (5.0, 0),
            (25.0, 2),
            (12.0, 1),
            (55.0, 4),
            (0.5, nil)
        ]

        for (seconds, expectedLine) in positions {
            let pos = tl.position(
                atPositionSeconds: seconds,
                outputLatencyMs: 0,
                globalOffsetMs: 0,
                manualLyricsOffsetMs: 0,
                hint: hint
            )
            #expect(pos.lineIndex == expectedLine, "At \(seconds)s expected line \(String(describing: expectedLine))")
            hint = pos.lineIndex
        }
    }
}
