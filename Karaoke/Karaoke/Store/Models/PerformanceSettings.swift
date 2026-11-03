import Foundation
import SwiftData

// MARK: - PerformanceSettings

/// The singer's audio controls. A singleton — one set, applied to whatever is
/// playing, persisted across songs and restarts (FR-028).
///
/// Fields:
/// - `outputVolume` — 0.0 … 1.0
/// - the tone control: three band gains and a bypass (FR-043)
///
/// There are no vocal fields — the PA speaker owns the microphone, its effects,
/// and the vocal-versus-music balance in hardware (FR-010).
/// There are no pitch or tempo fields — songs play as published (FR-011).
/// The tone control is not an exception to that: it shapes frequency response
/// and touches neither pitch nor tempo.
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

    // Defaults are declared inline so adding the tone control to an existing
    // store is a lightweight migration rather than a launch failure.
    private var _equalizerEnabled: Bool = false
    private var _equalizerBassDB: Double = 0
    private var _equalizerMidDB: Double = 0
    private var _equalizerTrebleDB: Double = 0

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

    /// The singer's tone control (FR-043).
    ///
    /// Clamped on read as well as write, for the same reason `outputVolume`
    /// is: a hand-edited or corrupted store must not push a 40 dB boost into
    /// a PA. `EqualizerSettings` does the clamping, so the rule lives in one
    /// place rather than being restated here.
    var equalizer: EqualizerSettings {
        get {
            EqualizerSettings(
                bassGainDB: _equalizerBassDB,
                midGainDB: _equalizerMidDB,
                trebleGainDB: _equalizerTrebleDB,
                isEnabled: _equalizerEnabled
            )
        }
        set {
            _equalizerBassDB = newValue.bassGainDB
            _equalizerMidDB = newValue.midGainDB
            _equalizerTrebleDB = newValue.trebleGainDB
            _equalizerEnabled = newValue.isEnabled
        }
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
