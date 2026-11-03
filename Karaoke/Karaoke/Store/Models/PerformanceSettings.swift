import Foundation
import SwiftData

// MARK: - PerformanceSettings

/// The singer's audio controls. A singleton — one set, applied to whatever is
/// playing, persisted across songs and restarts (FR-028).
///
/// **Exactly three fields** (data-model.md PerformanceSettings):
/// - `outputVolume`          — 0.0 … 1.0
/// - `manualLyricsOffsetMs`  — −2000 … +2000
/// - `lyricsFontScale`       — 0.5 … 3.0
///
/// There are no vocal fields — the PA speaker owns the microphone, its effects,
/// and the vocal-versus-music balance in hardware (FR-010).
/// There are no pitch or tempo fields — songs play as published (FR-011).
///
/// **Clamping on read AND write** (T023, data-model invariant 5):
/// A corrupted or hand-edited store must not push an out-of-range value at a
/// party PA. That is a speaker-damage and hearing-safety concern, not merely a
/// bad value. Every numeric accessor clamps before returning or storing.
@Model
final class PerformanceSettings {

    // MARK: Private backing storage
    // Stored with underscore names so the public computed properties can clamp.

    private var _outputVolume: Double
    private var _manualLyricsOffsetMs: Int
    private var _lyricsFontScale: Double

    // MARK: Ranges (static so tests can reference them without an instance)

    /// Valid range for `outputVolume` (FR-013).
    static let outputVolumeRange: ClosedRange<Double> = 0.0 ... 1.0

    /// Valid range for `manualLyricsOffsetMs` (FR-020).
    static let manualLyricsOffsetMsRange: ClosedRange<Int> = -2000 ... 2000

    /// Valid range for `lyricsFontScale` (FR-024).
    static let lyricsFontScaleRange: ClosedRange<Double> = 0.5 ... 3.0

    // MARK: Public clamped accessors (T023)

    /// Output volume applied to the audio pipeline.
    ///
    /// Clamped to 0.0 … 1.0 on **both read and write** (data-model invariant 5,
    /// T023). An out-of-range value reaching a party PA is a hearing-safety
    /// concern, not merely a bad value.
    var outputVolume: Double {
        get { _outputVolume.clamped(to: Self.outputVolumeRange) }
        set { _outputVolume = newValue.clamped(to: Self.outputVolumeRange) }
    }

    /// Manual correction added on top of the route's automatically detected
    /// output delay (FR-020).
    ///
    /// Clamped to −2000 … +2000 ms on **both read and write** (data-model
    /// invariant 5, T023). Resetting to 0 restores automatic behaviour.
    /// Exists because Bluetooth speakers frequently misreport their own latency.
    var manualLyricsOffsetMs: Int {
        get { _manualLyricsOffsetMs.clamped(to: Self.manualLyricsOffsetMsRange) }
        set { _manualLyricsOffsetMs = newValue.clamped(to: Self.manualLyricsOffsetMsRange) }
    }

    /// Scale factor applied to the lyrics display font (FR-024).
    ///
    /// Clamped to 0.5 … 3.0 on **both read and write** (data-model invariant 5,
    /// T023). Legible at room viewing distance on iPad.
    var lyricsFontScale: Double {
        get { _lyricsFontScale.clamped(to: Self.lyricsFontScaleRange) }
        set { _lyricsFontScale = newValue.clamped(to: Self.lyricsFontScaleRange) }
    }

    // MARK: Init

    /// Creates the singleton with spec-defined defaults.
    init(
        outputVolume: Double = 1.0,
        manualLyricsOffsetMs: Int = 0,
        lyricsFontScale: Double = 1.0
    ) {
        // Clamp at construction so a programmatic out-of-range init is also safe.
        self._outputVolume = outputVolume.clamped(to: Self.outputVolumeRange)
        self._manualLyricsOffsetMs = manualLyricsOffsetMs.clamped(to: Self.manualLyricsOffsetMsRange)
        self._lyricsFontScale = lyricsFontScale.clamped(to: Self.lyricsFontScaleRange)
    }
}

// MARK: - Clamping helpers

extension Comparable {
    /// Returns `self` clamped to `range`.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
