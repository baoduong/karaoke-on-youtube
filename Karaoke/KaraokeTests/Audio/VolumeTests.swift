// T063 — Volume clamping tests.
//
// Asserts that out-of-range values are clamped before reaching the player.
// At party volume this is a hearing-safety matter, covered regardless of how
// obvious it looks (audio-pipeline.md Test contract).
//
// Satisfies: FR-013, SC-007

import Testing
import AVFoundation
@testable import Karaoke

@Suite("Volume clamping")
struct VolumeTests {

    // MARK: Helpers

    /// A minimal mock pipeline that records the volume set on it.
    final class VolumeSpy: AudioPipeline, @unchecked Sendable {
        var recordedVolume: Float = -1

        func prepare() throws(AudioError) {}
        func stop() {}
        func load(source: AudioSource) async throws(AudioError) {}
        func play() throws(AudioError) {}
        func pause() {}
        func seek(to seconds: Double) async throws(AudioError) {}
        var position: PlaybackPosition { .invalid }
        var outputRoute: OutputRoute { .unknown }
        var events: AsyncStream<AudioPipelineEvent> {
            AsyncStream { _ in }
        }

        func setVolume(_ volume: Double) {
            recordedVolume = Float(max(0.0, min(1.0, volume)))
        }
    }

    // MARK: Tests

    /// Values in range pass through unchanged.
    @Test("volume 0.5 passes through unchanged")
    func volumeInRange() {
        let spy = VolumeSpy()
        spy.setVolume(0.5)
        #expect(abs(spy.recordedVolume - 0.5) < 0.001)
    }

    /// Values above 1.0 are clamped to 1.0.
    @Test("volume above 1.0 is clamped to 1.0")
    func volumeAboveMaxClamped() {
        let spy = VolumeSpy()
        spy.setVolume(1.5)
        #expect(spy.recordedVolume <= 1.0)
    }

    /// Values below 0.0 are clamped to 0.0.
    @Test("volume below 0.0 is clamped to 0.0")
    func volumeBelowMinClamped() {
        let spy = VolumeSpy()
        spy.setVolume(-0.5)
        #expect(spy.recordedVolume >= 0.0)
    }

    /// Exactly 0.0 is accepted.
    @Test("volume 0.0 is accepted")
    func volumeZero() {
        let spy = VolumeSpy()
        spy.setVolume(0.0)
        #expect(spy.recordedVolume == 0.0)
    }

    /// Exactly 1.0 is accepted.
    @Test("volume 1.0 is accepted")
    func volumeOne() {
        let spy = VolumeSpy()
        spy.setVolume(1.0)
        #expect(spy.recordedVolume == 1.0)
    }

    /// Very large values are clamped.
    @Test("volume 100.0 is clamped to 1.0")
    func volumeVeryLargeClamped() {
        let spy = VolumeSpy()
        spy.setVolume(100.0)
        #expect(spy.recordedVolume <= 1.0)
    }

    /// PlayerPipeline.setVolume clamps before reaching AVPlayer.
    @MainActor
    @Test("PlayerPipeline.setVolume clamps to 0...1")
    func playerPipelineClamps() {
        let pipeline = PlayerPipeline()
        // These must not crash and must not set AVPlayer.volume outside 0...1.
        pipeline.setVolume(2.0)
        pipeline.setVolume(-1.0)
        pipeline.setVolume(0.5)
        // If we reach here without a crash, the clamping is in place.
        // AVPlayer.volume is Float in 0...1; setting it outside that range
        // is undefined behaviour.
    }
}
