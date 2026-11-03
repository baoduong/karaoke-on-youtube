// T074 — LyricsParser.
//
// Parses LRC-format synchronized lyrics and validates them against the five
// rejection rules from contracts/lyrics-provider.md.
//
// Rejection rules (contracts/lyrics-provider.md Parsing and validation):
//   1. Line start times not strictly increasing.
//   2. A line's end time not > its start, or exceeds the next line's start.
//   3. Word start times not strictly increasing or outside the enclosing line's bounds.
//   4. Last start time exceeds song duration by more than a small tolerance.
//   5. Track is empty or contains no timed entries.
//
// Empty text on a timed line is NOT a rejection — it is a legitimate
// instrumental-gap marker.
//
// Satisfies: FR-022, contracts/lyrics-provider.md Parsing and validation

import Foundation
import os.log

// MARK: - ParseRejectionReason

/// Why a lyrics track was rejected. Logged locally; never shown to the singer.
enum ParseRejectionReason: Sendable, Equatable {
    /// Rule 1: line start times are not strictly increasing.
    case nonMonotonicLineStarts
    /// Rule 2: a line's end time is invalid.
    case invalidLineEndTime
    /// Rule 3: word start times are invalid within a line.
    case invalidWordTiming
    /// Rule 4: last start time exceeds song duration beyond tolerance.
    case durationMismatch(lastStartMs: Int, songDurationMs: Int)
    /// Rule 5: track is empty or has no timed entries.
    case emptyTrack
}

// MARK: - LyricsParser

/// Parses LRC-format text into a validated `LyricsTrackData`.
///
/// Returns `nil` when any of the five rejection rules fires, logging the reason
/// locally. Rejection is not an error — it means the track is unusable and the
/// app proceeds with the video image.
struct LyricsParser: Sendable {

    /// Tolerance for rule 4: last start time may exceed song duration by this
    /// many milliseconds before the track is rejected as mismatched.
    static let durationToleranceMs: Int = 5_000

    private static let parserLog = Logger(
        subsystem: "com.karaoke.personal",
        category: "lyrics-parser"
    )

    // MARK: Public API

    /// Parse and validate an LRC string.
    ///
    /// - Parameters:
    ///   - lrc: The raw LRC text.
    ///   - songID: Foreign key for the resulting track.
    ///   - source: Which provider supplied the text.
    ///   - hasWordSync: Whether the provider indicated word-level timing.
    ///   - songDurationSeconds: Used for rule 4 (duration mismatch).
    /// - Returns: A validated track, or `nil` if any rejection rule fires.
    func parse(
        lrc: String,
        songID: String,
        source: LyricsSource,
        hasWordSync: Bool,
        songDurationSeconds: Int
    ) -> LyricsTrackData? {
        let lines = parseLRCLines(lrc)

        if let reason = validate(lines: lines, songDurationSeconds: songDurationSeconds) {
            Self.parserLog.info(
                "LyricsParser rejected track songID=\(songID, privacy: .public) reason=\(String(describing: reason), privacy: .public)"
            )
            return nil
        }

        return LyricsTrackData(
            songID: songID,
            source: source,
            hasWordTiming: hasWordSync && lines.contains { !$0.words.isEmpty },
            globalOffsetMs: 0,
            fetchedAt: Date(),
            lines: lines
        )
    }

    // MARK: Private — LRC parsing

    /// Parses LRC lines from the raw text.
    ///
    /// LRC format: `[mm:ss.xx] text` per line.
    /// Extended word-level: `[mm:ss.xx] <mm:ss.xx> word <mm:ss.xx> word ...`
    private func parseLRCLines(_ lrc: String) -> [LyricsLineData] {
        var result: [LyricsLineData] = []
        var lineIndex = 0

        for rawLine in lrc.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Match the leading timestamp: [mm:ss.xx] or [mm:ss.xxx]
            guard let (startMs, remainder) = parseLeadingTimestamp(trimmed) else { continue }

            // Try to parse word-level timing from the remainder.
            let words = parseWords(remainder, lineIndex: lineIndex, lineStartMs: startMs)

            result.append(LyricsLineData(
                index: lineIndex,
                startMs: startMs,
                endMs: nil,
                text: stripWordTimestamps(remainder).trimmingCharacters(in: .whitespaces),
                words: words
            ))
            lineIndex += 1
        }

        return result
    }

    /// Parses `[mm:ss.xx]` from the start of a string.
    /// Returns (milliseconds, remainder after the bracket) or nil.
    private func parseLeadingTimestamp(_ s: String) -> (Int, String)? {
        guard s.hasPrefix("[") else { return nil }
        guard let closeIdx = s.firstIndex(of: "]") else { return nil }
        let inner = String(s[s.index(after: s.startIndex)..<closeIdx])
        guard let ms = parseTimestampMs(inner) else { return nil }
        let after = String(s[s.index(after: closeIdx)...])
        return (ms, after)
    }

    /// Parses `mm:ss.xx` or `mm:ss.xxx` into milliseconds.
    private func parseTimestampMs(_ s: String) -> Int? {
        // Accept mm:ss.xx, mm:ss.xxx, mm:ss (no decimal)
        let parts = s.components(separatedBy: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]) else { return nil }

        let secParts = parts[1].components(separatedBy: ".")
        guard let seconds = Int(secParts[0]) else { return nil }

        var ms = (minutes * 60 + seconds) * 1000
        if secParts.count == 2 {
            let fracStr = secParts[1]
            // Normalise to milliseconds: 2 digits = centiseconds, 3 = ms
            switch fracStr.count {
            case 1:
                ms += (Int(fracStr) ?? 0) * 100
            case 2:
                ms += (Int(fracStr) ?? 0) * 10
            case 3:
                ms += Int(fracStr) ?? 0
            default:
                // More than 3 digits: take first 3
                ms += Int(fracStr.prefix(3)) ?? 0
            }
        }
        return ms
    }

    /// Parses word-level timestamps from a line remainder.
    ///
    /// Extended LRC word format: `<mm:ss.xx> word <mm:ss.xx> word ...`
    private func parseWords(_ remainder: String, lineIndex: Int, lineStartMs: Int) -> [LyricsWordData] {
        guard remainder.contains("<") else { return [] }

        var words: [LyricsWordData] = []
        var wordIndex = 0
        var current = remainder

        while let openIdx = current.firstIndex(of: "<") {
            guard let closeIdx = current[current.index(after: openIdx)...].firstIndex(of: ">") else { break }
            let inner = String(current[current.index(after: openIdx)..<closeIdx])
            guard let startMs = parseTimestampMs(inner) else { break }

            let afterClose = current.index(after: closeIdx)
            let rest = String(current[afterClose...])

            // Text runs until the next `<` or end of string.
            let wordText: String
            if let nextOpen = rest.firstIndex(of: "<") {
                wordText = String(rest[..<nextOpen]).trimmingCharacters(in: .whitespaces)
                current = String(rest[nextOpen...])
            } else {
                wordText = rest.trimmingCharacters(in: .whitespaces)
                current = ""
            }

            if !wordText.isEmpty {
                words.append(LyricsWordData(
                    lineIndex: lineIndex,
                    index: wordIndex,
                    startMs: startMs,
                    text: wordText
                ))
                wordIndex += 1
            }
        }

        return words
    }

    private func stripWordTimestamps(_ s: String) -> String {
        var result = s
        while let open = result.firstIndex(of: "<"),
              let close = result[result.index(after: open)...].firstIndex(of: ">") {
            result.removeSubrange(open...close)
        }
        // Collapse runs of whitespace left by removed timestamps into single spaces.
        let components = result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    // MARK: Private — validation (five rejection rules)

    private func validate(lines: [LyricsLineData], songDurationSeconds: Int) -> ParseRejectionReason? {
        // Rule 5: empty or no timed entries.
        if lines.isEmpty { return .emptyTrack }

        let songDurationMs = songDurationSeconds * 1000

        for i in lines.indices {
            let line = lines[i]
            let nextLine = i + 1 < lines.count ? lines[i + 1] : nil

            // Rule 1: line start times must be strictly increasing.
            if i > 0, line.startMs <= lines[i - 1].startMs {
                return .nonMonotonicLineStarts
            }

            // Rule 2: end time validity.
            if let endMs = line.endMs {
                if endMs <= line.startMs { return .invalidLineEndTime }
                if let next = nextLine, endMs > next.startMs { return .invalidLineEndTime }
            }

            // Rule 3: word timing validity.
            if !line.words.isEmpty {
                for j in line.words.indices {
                    let word = line.words[j]
                    // Words must be within the enclosing line's bounds.
                    if word.startMs < line.startMs { return .invalidWordTiming }
                    if let endMs = line.endMs, word.startMs >= endMs { return .invalidWordTiming }
                    // Words must be strictly increasing within the line.
                    if j > 0, word.startMs <= line.words[j - 1].startMs { return .invalidWordTiming }
                }
            }
        }

        // Rule 4: last start time must not exceed song duration by more than tolerance.
        if let lastLine = lines.last {
            let excess = lastLine.startMs - songDurationMs
            if excess > Self.durationToleranceMs {
                return .durationMismatch(lastStartMs: lastLine.startMs, songDurationMs: songDurationMs)
            }
        }

        return nil
    }
}

// MARK: - LyricsParser (internal validation access for tests)

extension LyricsParser {
    /// Exposed for tests — validates a pre-built line array.
    func validateLines(_ lines: [LyricsLineData], songDurationSeconds: Int) -> ParseRejectionReason? {
        validate(lines: lines, songDurationSeconds: songDurationSeconds)
    }
}
