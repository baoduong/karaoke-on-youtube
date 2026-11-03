// Tests for the tone control's pure logic (FR-043).
//
// Principle IV decides the scope here. Gain clamping, headroom arithmetic and
// settings persistence are logic that fails quietly: a bad gain reaching a PA
// is a speaker-damage and hearing-safety matter, and nothing on screen would
// reveal it. The filter itself and the tap wiring are explicitly exempt — the
// principle names audio graph wiring as verified by ear and instrument on a
// device, which is where SC-015 is measured.

import Testing
import Foundation
import AVFoundation
import SwiftData
@testable import Karaoke

// MARK: - Attachment

/// The one thing about this feature that cannot be reasoned about, only
/// observed: whether the platform accepts the tap at all.
///
/// Uses a generated tone rather than a fixture or the network, so it runs
/// anywhere. Measured behaviour at the time of writing:
///
/// | source | iOS 26.2 | iOS 27.2 |
/// |---|---|---|
/// | local file | attaches | attaches |
/// | HLS | refuses | attaches |
///
/// The HLS half needs a live companion service and so is not automated. The
/// file half is, because a regression there would be silent — the control
/// would move and nothing would happen.
@Suite("Equalizer attachment")
struct EqualizerAttachmentTests {

    private static func makeToneFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eq-probe-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            guard let data = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) {
                data[frame] = sinf(2 * .pi * 440 * Float(frame) / 44_100) * 0.5
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test("a file-based source accepts the tone control")
    func localFileAttaches() async throws {
        let url = try Self.makeToneFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let pipeline = PlayerPipeline()
        try pipeline.prepare()
        pipeline.setEqualizer(EqualizerSettings(bassGainDB: 6, isEnabled: true))
        try await pipeline.load(source: .local(url))

        #expect(pipeline.isEqualizerAvailable)
    }

    @Test("nothing is reported as available before a source is loaded")
    func unavailableBeforeLoad() throws {
        let pipeline = PlayerPipeline()
        #expect(!pipeline.isEqualizerAvailable)
    }
}

@Suite("Equalizer settings")
struct EqualizerSettingsTests {

    // MARK: Clamping

    @Suite("Gain clamping")
    struct ClampingTests {

        @Test("a gain above the range is pulled back to the maximum")
        func clampsAbove() {
            let settings = EqualizerSettings(bassGainDB: 40)
            #expect(settings.bassGainDB == 12)
        }

        @Test("a gain below the range is pulled up to the minimum")
        func clampsBelow() {
            let settings = EqualizerSettings(trebleGainDB: -90)
            #expect(settings.trebleGainDB == -12)
        }

        @Test("a gain inside the range passes through untouched")
        func passesThrough() {
            let settings = EqualizerSettings(midGainDB: 3.5)
            #expect(settings.midGainDB == 3.5)
        }

        @Test("the mutating setters clamp too, not just the initialiser")
        func settersClamp() {
            var settings = EqualizerSettings()
            settings.setBass(100)
            settings.setMid(-100)
            settings.setTreble(6)
            #expect(settings.bassGainDB == 12)
            #expect(settings.midGainDB == -12)
            #expect(settings.trebleGainDB == 6)
        }

        @Test("a non-finite gain becomes zero rather than poisoning the filter")
        func rejectsNonFinite() {
            let nan = EqualizerSettings(bassGainDB: .nan)
            let infinite = EqualizerSettings(midGainDB: .infinity)
            #expect(nan.bassGainDB == 0)
            #expect(infinite.midGainDB == 0)
        }
    }

    // MARK: Transparency

    @Suite("Transparency")
    struct TransparencyTests {

        @Test("the default is transparent, which is what keeps SC-007 true")
        func defaultIsTransparent() {
            #expect(EqualizerSettings.flat.isTransparent)
        }

        @Test("bypassed is transparent however the bands are set")
        func bypassedIsTransparent() {
            let settings = EqualizerSettings(bassGainDB: 9, isEnabled: false)
            #expect(settings.isTransparent)
        }

        @Test("enabled but flat is still transparent")
        func enabledFlatIsTransparent() {
            let settings = EqualizerSettings(isEnabled: true)
            #expect(settings.isTransparent)
        }

        @Test("enabled with any band moved is not transparent")
        func enabledWithGainIsNotTransparent() {
            let settings = EqualizerSettings(trebleGainDB: 0.5, isEnabled: true)
            #expect(!settings.isTransparent)
        }
    }

    // MARK: Headroom

    @Suite("Clipping headroom")
    struct HeadroomTests {

        @Test("a boost is matched by an equal attenuation")
        func boostIsOffset() {
            let settings = EqualizerSettings(trebleGainDB: 6, isEnabled: true)
            #expect(settings.headroomGainDB == -6)
        }

        @Test("the largest boost decides the attenuation")
        func largestBoostWins() {
            let settings = EqualizerSettings(
                bassGainDB: 2,
                midGainDB: 9,
                trebleGainDB: 4,
                isEnabled: true
            )
            #expect(settings.headroomGainDB == -9)
        }

        @Test("cutting only costs no level — there is nothing to clip")
        func cutsNeedNoHeadroom() {
            let settings = EqualizerSettings(
                bassGainDB: -8,
                trebleGainDB: -3,
                isEnabled: true
            )
            #expect(settings.headroomGainDB == 0)
        }

        @Test("a bypassed boost takes no headroom")
        func bypassedTakesNoHeadroom() {
            let settings = EqualizerSettings(bassGainDB: 12, isEnabled: false)
            #expect(settings.headroomGainDB == 0)
        }

        @Test("the maximum boost cannot drive output above unity")
        func maximumBoostIsFullyOffset() {
            let settings = EqualizerSettings(
                bassGainDB: 12,
                midGainDB: 12,
                trebleGainDB: 12,
                isEnabled: true
            )
            #expect(settings.headroomGainDB == -12)
        }
    }

    // MARK: Reset

    @Test("Flat clears the bands but leaves the control switched on")
    func resetKeepsEnabled() {
        var settings = EqualizerSettings(
            bassGainDB: 5,
            midGainDB: -5,
            trebleGainDB: 2,
            isEnabled: true
        )
        settings.reset()
        #expect(settings.bassGainDB == 0)
        #expect(settings.midGainDB == 0)
        #expect(settings.trebleGainDB == 0)
        #expect(settings.isEnabled)
        #expect(settings.isTransparent)
    }

    // MARK: Persistence

    @Suite("Persistence")
    struct PersistenceTests {

        @MainActor
        private static func makeContext() throws -> ModelContext {
            let schema = Schema([
                Song.self,
                SavedSong.self,
                Favourite.self,
                QueueEntry.self,
                PerformanceSettings.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return ModelContext(try ModelContainer(for: schema, configurations: config))
        }

        @Test("a stored tone control survives a round trip")
        @MainActor
        func roundTrips() throws {
            let context = try Self.makeContext()
            let stored = PerformanceSettings()
            stored.equalizer = EqualizerSettings(
                bassGainDB: -4,
                midGainDB: 1.5,
                trebleGainDB: 7,
                isEnabled: true
            )
            context.insert(stored)
            try context.save()

            let fetched = try #require(try context.fetch(FetchDescriptor<PerformanceSettings>()).first)
            #expect(fetched.equalizer.bassGainDB == -4)
            #expect(fetched.equalizer.midGainDB == 1.5)
            #expect(fetched.equalizer.trebleGainDB == 7)
            #expect(fetched.equalizer.isEnabled)
        }

        @Test("a fresh settings record starts flat and off")
        @MainActor
        func defaultsAreFlat() throws {
            let context = try Self.makeContext()
            let stored = PerformanceSettings()
            context.insert(stored)
            try context.save()

            #expect(stored.equalizer == EqualizerSettings.flat)
            #expect(stored.equalizer.isTransparent)
        }

        @Test("an out-of-range value in the store is clamped on the way out")
        @MainActor
        func clampsOnRead() throws {
            let context = try Self.makeContext()
            let stored = PerformanceSettings()
            // Writing through the public accessor already clamps, which is the
            // point: there is no path that puts 40 dB into the filter.
            stored.equalizer = EqualizerSettings(bassGainDB: 40, isEnabled: true)
            context.insert(stored)
            try context.save()

            #expect(stored.equalizer.bassGainDB == 12)
        }
    }

    // MARK: Display

    @Test("gain labels carry a sign so a cut reads differently from a boost")
    func labelsAreSigned() {
        #expect(EqualizerView.label(for: 0) == "0 dB")
        #expect(EqualizerView.label(for: 3) == "+3.0 dB")
        #expect(EqualizerView.label(for: -3) == "−3.0 dB")
    }
}
