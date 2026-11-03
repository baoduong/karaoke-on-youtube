// T084 — LyricsValidationTests.
//
// Exercises each of the five rejection rules. The duration-mismatch rule is
// covered explicitly — it is what prevents the wrong song's words appearing.
//
// Satisfies: contracts/lyrics-provider.md Test contract (Validation)

import Testing
import Foundation
@testable import Karaoke

@Suite("LyricsValidation")
struct LyricsValidationTests {

    let parser = LyricsParser()

    // MARK: Rule 1 — non-monotonic line starts

    @Test("Rule 1: rejects track with non-strictly-increasing line start times")
    func rejectsNonMonotonicLineStarts() {
        let lrc = """
        [00:05.00] alpha
        [00:03.00] bravo
        [00:10.00] charlie
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track == nil)
    }

    @Test("Rule 1: rejects track where two lines share the same start time")
    func rejectsDuplicateLineStartTimes() {
        let lrc = """
        [00:05.00] alpha
        [00:05.00] bravo
        [00:10.00] charlie
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track == nil)
    }

    // MARK: Rule 2 — invalid line end time

    @Test("Rule 2: rejects line whose endMs is not greater than startMs")
    func rejectsEndTimeNotGreaterThanStart() {
        let lines = [
            LyricsLineData(index: 0, startMs: 1_000, endMs: 1_000, text: "alpha", words: []),
            LyricsLineData(index: 1, startMs: 5_000, endMs: nil, text: "bravo", words: [])
        ]
        let reason = parser.validateLines(lines, songDurationSeconds: 60)
        #expect(reason == .invalidLineEndTime)
    }

    @Test("Rule 2: rejects line whose endMs exceeds the next line's startMs")
    func rejectsEndTimeExceedingNextLineStart() {
        let lines = [
            LyricsLineData(index: 0, startMs: 1_000, endMs: 8_000, text: "alpha", words: []),
            LyricsLineData(index: 1, startMs: 5_000, endMs: nil, text: "bravo", words: [])
        ]
        let reason = parser.validateLines(lines, songDurationSeconds: 60)
        #expect(reason == .invalidLineEndTime)
    }

    @Test("Rule 2: accepts line whose endMs equals the next line's startMs")
    func acceptsEndTimeEqualToNextLineStart() {
        let lines = [
            LyricsLineData(index: 0, startMs: 1_000, endMs: 5_000, text: "alpha", words: []),
            LyricsLineData(index: 1, startMs: 5_000, endMs: nil, text: "bravo", words: [])
        ]
        let reason = parser.validateLines(lines, songDurationSeconds: 60)
        #expect(reason == nil)
    }

    // MARK: Rule 3 — invalid word timing

    @Test("Rule 3: rejects word whose startMs is before the enclosing line's startMs")
    func rejectsWordBeforeLineStart() {
        let lines = [
            LyricsLineData(
                index: 0,
                startMs: 5_000,
                endMs: nil,
                text: "alpha bravo",
                words: [
                    LyricsWordData(lineIndex: 0, index: 0, startMs: 4_000, text: "alpha"),
                    LyricsWordData(lineIndex: 0, index: 1, startMs: 5_500, text: "bravo")
                ]
            )
        ]
        let reason = parser.validateLines(lines, songDurationSeconds: 60)
        #expect(reason == .invalidWordTiming)
    }

    @Test("Rule 3: rejects non-strictly-increasing word start times within a line")
    func rejectsNonMonotonicWordStarts() {
        let lines = [
            LyricsLineData(
                index: 0,
                startMs: 1_000,
                endMs: nil,
                text: "alpha bravo charlie",
                words: [
                    LyricsWordData(lineIndex: 0, index: 0, startMs: 1_000, text: "alpha"),
                    LyricsWordData(lineIndex: 0, index: 1, startMs: 3_000, text: "bravo"),
                    LyricsWordData(lineIndex: 0, index: 2, startMs: 2_000, text: "charlie")
                ]
            )
        ]
        let reason = parser.validateLines(lines, songDurationSeconds: 60)
        #expect(reason == .invalidWordTiming)
    }

    @Test("Rule 3: rejects word whose startMs is at or after the line's endMs")
    func rejectsWordAtOrAfterLineEnd() {
        let lines = [
            LyricsLineData(
                index: 0,
                startMs: 1_000,
                endMs: 5_000,
                text: "alpha bravo",
                words: [
                    LyricsWordData(lineIndex: 0, index: 0, startMs: 1_000, text: "alpha"),
                    LyricsWordData(lineIndex: 0, index: 1, startMs: 5_000, text: "bravo")
                ]
            )
        ]
        let reason = parser.validateLines(lines, songDurationSeconds: 60)
        #expect(reason == .invalidWordTiming)
    }

    // MARK: Rule 4 — duration mismatch

    @Test("Rule 4: rejects track whose last startMs exceeds song duration beyond tolerance")
    func rejectsDurationMismatch() {
        // Song is 60 s = 60000 ms. Last line at 70000 ms = 10000 ms over.
        // Tolerance is 5000 ms, so 10000 ms over should be rejected.
        let lrc = """
        [00:01.00] alpha
        [01:10.00] bravo
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track == nil)
    }

    @Test("Rule 4: accepts track whose last startMs is within tolerance of song duration")
    func acceptsTrackWithinDurationTolerance() {
        // Song is 60 s = 60000 ms. Last line at 63000 ms = 3000 ms over.
        // Tolerance is 5000 ms, so this should be accepted.
        let lrc = """
        [00:01.00] alpha
        [01:03.00] bravo
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track != nil)
    }

    @Test("Rule 4: duration mismatch is what prevents wrong song's words appearing")
    func durationMismatchPreventsWrongSong() {
        // A track for a 4-minute song queried against a 1-minute song.
        let lrc = """
        [00:01.00] alpha
        [03:50.00] bravo
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track == nil)
    }

    // MARK: Rule 5 — empty track

    @Test("Rule 5: rejects empty LRC string")
    func rejectsEmptyLRC() {
        let track = parser.parse(
            lrc: "",
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track == nil)
    }

    @Test("Rule 5: rejects LRC with no timed entries")
    func rejectsLRCWithNoTimedEntries() {
        let lrc = """
        [ar: Some Artist]
        [ti: Some Title]
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track == nil)
    }

    // MARK: Valid track passes all rules

    @Test("Valid track with all rules satisfied is accepted")
    func validTrackIsAccepted() {
        let lrc = """
        [00:01.00] alpha bravo
        [00:05.00] charlie delta
        [00:10.00] echo foxtrot
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.lines.count == 3)
    }
}
