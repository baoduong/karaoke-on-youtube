import Foundation
import SwiftData

// MARK: - PerformanceSettings

/// The singer's audio controls. A singleton — one set, applied to whatever is
/// playing, persisted across songs and restarts (FR-028).
///
/// **Exactly three fields** (data-model.md PerformanceSettings):
/// - `outputVolume`          — 0.0 … 1.0
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

    // MARK: Ranges (static so tests can reference them without an instance)

    /// Valid range for `outputVolume` (FR-013).
    static let outputVolumeRange: ClosedRange<Double> = 0.0 ... 1.0



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

    // MARK: Init

    /// Creates the singleton with spec-defined defaults.
    init(outputVolume: Double = 1.0) {
        // Clamp at construction so a programmatic out-of-range init is also safe.
        self._outputVolume = outputVolume.clamped(to: Self.outputVolumeRange)
    }
}

// MARK: - Clamping helpers

extension Comparable {
    /// Returns `self` clamped to `range`.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
