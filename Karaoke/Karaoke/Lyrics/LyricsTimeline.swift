// T075, T076 — LyricsTimeline.
//
// Pure lookup: no allocation, no I/O, callable at display refresh rate.
// Binary search with previous-index hint (T076).
//
// THE FORMULA (contracts/lyrics-provider.md Timing contract Rule 4,
// data-model.md Timing rules):
//
//   effectiveMs = positionMs - outputLatencyMs + globalOffsetMs + manualLyricsOffsetMs
//
// The subtraction of outputLatencyMs is the point. The player reports what was
// dispatched; the Bluetooth speaker emits it later. Because Bluetooth is the
// only supported route, omitting this is wrong for every song.
//
// Satisfies: FR-019, FR-020, FR-023, SC-008, contracts/lyrics-provider.md

import Foundation

// MARK: - LyricsPosition

/// The resolved position within a lyrics track at a given effective time.
struct LyricsPosition: Sendable, Equatable {
    /// nil before the first line or after the last.
    let lineIndex: Int?
    /// nil when the track has no word timing.
    let wordIndex: Int?
    /// 0…1 progress within the current word, for a smooth wipe.
    let progressWithinWord: Double
}

// MARK: - LyricsTimeline

/// Pure lookup over a lyrics track.
///
/// Lookup is O(log n) via binary search with a previous-index hint.
/// No allocation, no I/O — safe to call at display refresh rate (60 Hz).
struct LyricsTimeline: Sendable {

    private let lines: [LyricsLineData]
    /// Sorted array of line start times in milliseconds, parallel to `lines`.
    private let startTimes: [Int]

    init(track: LyricsTrackData) {
        self.lines = track.lines
        self.startTimes = track.lines.map(\.startMs)
    }

    // MARK: Public API

    /// Resolve the current position within the track.
    ///
    /// Effective time formula (contracts/lyrics-provider.md Rule 4):
    ///   effectiveMs = positionMs − outputLatencyMs + globalOffsetMs + manualLyricsOffsetMs
    ///
    /// - Parameters:
    ///   - positionSeconds: `PlaybackPosition.seconds` from the audio pipeline.
    ///   - outputLatencyMs: The active route's reported output delay (FR-019).
    ///   - globalOffsetMs: Track-level correction stored in `LyricsTrackData`.
    ///   - manualLyricsOffsetMs: Singer's manual trim from `PerformanceSettings`.
    ///   - hint: The line index returned by the previous call. Speeds up the
    ///     common case where playback advances by one line at a time.
    /// - Returns: The resolved position.
    func position(
        atPositionSeconds positionSeconds: Double,
        outputLatencyMs: Double,
        globalOffsetMs: Int,
        manualLyricsOffsetMs: Int,
        hint: Int? = nil
    ) -> LyricsPosition {
        guard !lines.isEmpty else {
            return LyricsPosition(lineIndex: nil, wordIndex: nil, progressWithinWord: 0)
        }

        // Effective time in milliseconds.
        // Rule 4: subtract outputLatencyMs so the display matches what the room hears.
        let effectiveMs = Int((positionSeconds * 1000) - outputLatencyMs)
            + globalOffsetMs
            + manualLyricsOffsetMs

        let lineIdx = findLineIndex(effectiveMs: effectiveMs, hint: hint)
        guard let lineIdx else {
            return LyricsPosition(lineIndex: nil, wordIndex: nil, progressWithinWord: 0)
        }

        let line = lines[lineIdx]
        let wordIdx = findWordIndex(effectiveMs: effectiveMs, in: line)
        let progress = wordProgress(effectiveMs: effectiveMs, wordIndex: wordIdx, in: line)

        return LyricsPosition(
            lineIndex: lineIdx,
            wordIndex: wordIdx,
            progressWithinWord: progress
        )
    }

    // MARK: Private — binary search with hint (T076)

    /// Returns the index of the line active at `effectiveMs`, or nil if before
    /// the first line or after the last.
    ///
    /// Uses the hint to skip the binary search when the position is still within
    /// the same line or has advanced by one — the common case during playback.
    private func findLineIndex(effectiveMs: Int, hint: Int?) -> Int? {
        guard !startTimes.isEmpty else { return nil }

        // Before the first line.
        if effectiveMs < startTimes[0] { return nil }

        // After the last line's start — check if we're past the end.
        let lastIdx = startTimes.count - 1
        if effectiveMs >= startTimes[lastIdx] {
            // If the last line has an explicit end time, check it.
            let lastLine = lines[lastIdx]
            if let endMs = lastLine.endMs, effectiveMs >= endMs { return nil }
            return lastIdx
        }

        // Try the hint first: check if effectiveMs is still within the hinted line.
        if let h = hint, h >= 0, h < lines.count {
            let hintStart = startTimes[h]
            let hintEnd = h + 1 < startTimes.count ? startTimes[h + 1] : Int.max
            if effectiveMs >= hintStart && effectiveMs < hintEnd {
                return h
            }
            // Try the next line (common case: playback advanced by one line).
            let next = h + 1
            if next < lines.count {
                let nextStart = startTimes[next]
                let nextEnd = next + 1 < startTimes.count ? startTimes[next + 1] : Int.max
                if effectiveMs >= nextStart && effectiveMs < nextEnd {
                    return next
                }
            }
        }

        // Binary search: find the last line whose startMs <= effectiveMs.
        var lo = 0
        var hi = startTimes.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if startTimes[mid] <= effectiveMs {
                lo = mid
            } else {
                hi = mid - 1
            }
        }

        // lo is the last line whose start <= effectiveMs.
        // Verify it hasn't ended.
        let candidate = lo
        let lineEnd = candidate + 1 < startTimes.count ? startTimes[candidate + 1] : Int.max
        if effectiveMs >= lineEnd { return nil }

        return candidate
    }

    /// Returns the word index active at `effectiveMs` within `line`, or nil.
    private func findWordIndex(effectiveMs: Int, in line: LyricsLineData) -> Int? {
        guard !line.words.isEmpty else { return nil }

        // Before the first word.
        if effectiveMs < line.words[0].startMs { return nil }

        // Binary search for the last word whose startMs <= effectiveMs.
        var lo = 0
        var hi = line.words.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if line.words[mid].startMs <= effectiveMs {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// Computes 0…1 progress within the current word.
    private func wordProgress(effectiveMs: Int, wordIndex: Int?, in line: LyricsLineData) -> Double {
        guard let wi = wordIndex, wi < line.words.count else { return 0 }

        let wordStart = line.words[wi].startMs
        let wordEnd: Int
        if wi + 1 < line.words.count {
            wordEnd = line.words[wi + 1].startMs
        } else if let lineEnd = line.endMs {
            wordEnd = lineEnd
        } else {
            return 1.0
        }

        let duration = wordEnd - wordStart
        guard duration > 0 else { return 1.0 }
        let elapsed = effectiveMs - wordStart
        return min(1.0, max(0.0, Double(elapsed) / Double(duration)))
    }
}
