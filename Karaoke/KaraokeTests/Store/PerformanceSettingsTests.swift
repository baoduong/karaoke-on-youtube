import Testing
@testable import Karaoke

// MARK: - PerformanceSettingsTests (T041)

/// Tests for PerformanceSettings clamping on read AND write (T023, data-model
/// invariant 5).
///
/// These tests exist because a corrupted or hand-edited store must not push an
/// out-of-range value at a party PA — that is a speaker-damage and
/// hearing-safety concern, not merely a bad value (data-model.md
/// PerformanceSettings Validation).
///
/// Constitution Principle IV: test what can silently rot. The clamping logic
/// is pure and fails silently if removed — exactly the category that needs tests.
@Suite("PerformanceSettings clamping")
struct PerformanceSettingsTests {

    // MARK: - outputVolume (range 0.0 … 1.0)

    @Suite("outputVolume")
    struct OutputVolumeTests {

        @Test("default value is 1.0")
        func defaultValue() {
            let settings = PerformanceSettings()
            #expect(settings.outputVolume == 1.0)
        }

        @Test("value within range is stored unchanged")
        func withinRange() {
            let settings = PerformanceSettings(outputVolume: 0.5)
            #expect(settings.outputVolume == 0.5)
        }

        @Test("lower bound 0.0 is accepted")
        func lowerBound() {
            let settings = PerformanceSettings(outputVolume: 0.0)
            #expect(settings.outputVolume == 0.0)
        }

        @Test("upper bound 1.0 is accepted")
        func upperBound() {
            let settings = PerformanceSettings(outputVolume: 1.0)
            #expect(settings.outputVolume == 1.0)
        }

        @Test("value below 0.0 is clamped to 0.0 on write")
        func clampedBelowOnWrite() {
            let settings = PerformanceSettings()
            settings.outputVolume = -0.1
            #expect(settings.outputVolume == 0.0)
        }

        @Test("value above 1.0 is clamped to 1.0 on write")
        func clampedAboveOnWrite() {
            let settings = PerformanceSettings()
            settings.outputVolume = 1.5
            #expect(settings.outputVolume == 1.0)
        }

        @Test("large negative value is clamped to 0.0 on write")
        func largeNegativeClampedOnWrite() {
            let settings = PerformanceSettings()
            settings.outputVolume = -999.0
            #expect(settings.outputVolume == 0.0)
        }

        @Test("large positive value is clamped to 1.0 on write")
        func largePositiveClampedOnWrite() {
            let settings = PerformanceSettings()
            settings.outputVolume = 999.0
            #expect(settings.outputVolume == 1.0)
        }

        @Test("out-of-range init value is clamped on read")
        func outOfRangeInitClampedOnRead() {
            // Simulate a corrupted store by constructing with an out-of-range
            // value. The getter must clamp regardless of what the backing store
            // contains (data-model invariant 5, T023).
            let settings = PerformanceSettings(outputVolume: 2.0)
            #expect(settings.outputVolume == 1.0)
        }
    }

    // MARK: - Range constants

    @Suite("Range constants")
    struct RangeConstantTests {

        @Test("outputVolumeRange is 0.0 … 1.0")
        func outputVolumeRange() {
            #expect(PerformanceSettings.outputVolumeRange == 0.0 ... 1.0)
        }


    }
}
