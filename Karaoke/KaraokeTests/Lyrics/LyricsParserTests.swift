// T083 — LyricsParserTests.
//
// Tests for well-formed line-level and word-level inputs.
// Fixtures use synthetic placeholder text only — no real song text.
//
// Satisfies: contracts/lyrics-provider.md Test contract (Parser)

import Testing
import Foundation
@testable import Karaoke

@Suite("LyricsParser")
struct LyricsParserTests {

    let parser = LyricsParser()

    // MARK: Line-level parsing

    @Test("Parses well-formed line-level LRC into correct structure")
    func parsesLineLevelLRC() {
        let lrc = """
        [00:01.00] alpha bravo
        [00:05.50] charlie delta
        [00:10.00] echo foxtrot
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.lines.count == 3)
        #expect(track?.lines[0].startMs == 1_000)
        #expect(track?.lines[0].text == "alpha bravo")
        #expect(track?.lines[1].startMs == 5_500)
        #expect(track?.lines[1].text == "charlie delta")
        #expect(track?.lines[2].startMs == 10_000)
        #expect(track?.lines[2].text == "echo foxtrot")
        #expect(track?.hasWordTiming == false)
    }

    @Test("Parses timestamps with two-digit centiseconds")
    func parsesTwoDigitCentiseconds() {
        let lrc = "[01:23.45] golf hotel"
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 300
        )
        #expect(track != nil)
        // 1 min 23 sec = 83 s = 83000 ms + 45 cs = 83450 ms
        #expect(track?.lines[0].startMs == 83_450)
    }

    @Test("Parses timestamps with three-digit milliseconds")
    func parsesThreeDigitMilliseconds() {
        let lrc = "[00:02.500] india juliet"
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.lines[0].startMs == 2_500)
    }

    @Test("Empty text on a timed line is accepted as instrumental-gap marker")
    func emptyTextLineIsAccepted() {
        let lrc = """
        [00:01.00] alpha
        [00:05.00]
        [00:10.00] bravo
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.lines.count == 3)
        #expect(track?.lines[1].text == "")
    }

    @Test("Skips lines without a leading timestamp")
    func skipsNonTimestampLines() {
        let lrc = """
        [ar: Some Artist]
        [ti: Some Title]
        [00:01.00] charlie
        [00:05.00] delta
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        // [ar:] and [ti:] don't parse as timestamps (non-numeric), so only 2 lines.
        #expect(track != nil)
        #expect(track?.lines.count == 2)
    }

    // MARK: Word-level parsing

    @Test("Parses well-formed word-level LRC into correct structure")
    func parsesWordLevelLRC() {
        let lrc = """
        [00:01.00] <00:01.00> alpha <00:01.50> bravo <00:02.00> charlie
        [00:05.00] <00:05.00> delta <00:05.80> echo
        """
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: true,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.hasWordTiming == true)
        #expect(track?.lines[0].words.count == 3)
        #expect(track?.lines[0].words[0].text == "alpha")
        #expect(track?.lines[0].words[0].startMs == 1_000)
        #expect(track?.lines[0].words[1].text == "bravo")
        #expect(track?.lines[0].words[1].startMs == 1_500)
        #expect(track?.lines[0].words[2].text == "charlie")
        #expect(track?.lines[0].words[2].startMs == 2_000)
        #expect(track?.lines[1].words.count == 2)
        #expect(track?.lines[1].words[0].text == "delta")
        #expect(track?.lines[1].words[1].text == "echo")
    }

    @Test("hasWordTiming is false when hasWordSync is false even if word timestamps present")
    func hasWordTimingRespectsSyncFlag() {
        let lrc = "[00:01.00] <00:01.00> alpha <00:01.50> bravo"
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.hasWordTiming == false)
    }

    @Test("Word text is stripped from line text")
    func wordTimestampsStrippedFromLineText() {
        let lrc = "[00:01.00] <00:01.00> golf <00:01.50> hotel"
        let track = parser.parse(
            lrc: lrc,
            songID: "test-song",
            source: .lrclib,
            hasWordSync: true,
            songDurationSeconds: 60
        )
        #expect(track != nil)
        #expect(track?.lines[0].text == "golf hotel")
    }

    @Test("Source and songID are preserved in the result")
    func preservesMetadata() {
        let lrc = "[00:01.00] india"
        let track = parser.parse(
            lrc: lrc,
            songID: "my-song-id",
            source: .lrclib,
            hasWordSync: false,
            songDurationSeconds: 60
        )
        #expect(track?.songID == "my-song-id")
        #expect(track?.source == .lrclib)
        #expect(track?.globalOffsetMs == 0)
    }
}
