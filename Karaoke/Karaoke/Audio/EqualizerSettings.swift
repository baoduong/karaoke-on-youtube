import Foundation

/// The singer's tone control: three bands and a bypass (FR-043).
///
/// Three bands, not ten. The need is "turn the treble up a bit, or the bass
/// down a bit" on an upload that sounds wrong through the PA; nine more
/// sliders would serve that no better while giving a singer holding a
/// microphone nine more things to get wrong.
struct EqualizerSettings: Sendable, Equatable {

    /// Conventional tone-control range. Wide enough to rescue a dull or boomy
    /// upload, narrow enough that it does not invite a boost that clips.
    static let gainRange: ClosedRange<Double> = -12...12

    static let flat = EqualizerSettings()

    /// Low shelf. Below this the PA's own bass response dominates anyway.
    static let bassFrequency: Float = 100

    /// Peaking band sitting where a vocal line lives, so a muddy or shrill
    /// backing track can be moved out of the singer's way.
    static let midFrequency: Float = 1_000

    /// High shelf. Air and consonants; what a dull upload is missing.
    static let trebleFrequency: Float = 8_000

    private(set) var bassGainDB: Double
    private(set) var midGainDB: Double
    private(set) var trebleGainDB: Double

    /// Bypass. Off by default, which is what keeps SC-007's bit-identity
    /// claim true for anyone who never touches this.
    var isEnabled: Bool

    init(
        bassGainDB: Double = 0,
        midGainDB: Double = 0,
        trebleGainDB: Double = 0,
        isEnabled: Bool = false
    ) {
        self.bassGainDB = Self.clamp(bassGainDB)
        self.midGainDB = Self.clamp(midGainDB)
        self.trebleGainDB = Self.clamp(trebleGainDB)
        self.isEnabled = isEnabled
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, gainRange.lowerBound), gainRange.upperBound)
    }

    mutating func setBass(_ value: Double) { bassGainDB = Self.clamp(value) }
    mutating func setMid(_ value: Double) { midGainDB = Self.clamp(value) }
    mutating func setTreble(_ value: Double) { trebleGainDB = Self.clamp(value) }

    mutating func reset() {
        bassGainDB = 0
        midGainDB = 0
        trebleGainDB = 0
    }

    /// True when the settings cannot change the signal, whether because they
    /// are bypassed or because every band sits at zero. The pipeline uses
    /// this to skip attaching a tap at all.
    var isTransparent: Bool {
        !isEnabled || (bassGainDB == 0 && midGainDB == 0 && trebleGainDB == 0)
    }

    /// Overall attenuation applied alongside the bands, in dB.
    ///
    /// Boosting a band on material already mastered near full scale clips.
    /// Rather than add a limiter — dynamics processing the singer did not ask
    /// for, and a second thing to reason about on the render thread — the
    /// output is pulled down by as much as the largest boost. Level is the
    /// cheap thing to give away here; the PA has its own volume control.
    ///
    /// Conservative on purpose: it assumes the worst case where bands overlap
    /// and sum. Cutting only, or leaving everything flat, costs nothing.
    var headroomGainDB: Double {
        guard isEnabled else { return 0 }
        let largestBoost = max(0, max(bassGainDB, max(midGainDB, trebleGainDB)))
        return -largestBoost
    }
}
