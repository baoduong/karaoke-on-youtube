import AVFoundation
import Foundation
import Testing
@testable import Karaoke

/// Route classification, which decides three things the singer notices:
/// whether playback pauses when the speaker drops (FR-018), whether the app
/// admits the link is degrading quality (FR-014), and how far the on-screen
/// words must be shifted (FR-019).
///
/// A real Bluetooth disconnect cannot be staged in a unit test, so the
/// behaviour that is testable here is the pure classification these decisions
/// are derived from.
@Suite("Output route classification")
struct OutputLossTests {

    @Test("Port types map to the expected route kind", arguments: [
        (AVAudioSession.Port.bluetoothA2DP, RouteKind.bluetoothA2DP),
        (.builtInSpeaker, .builtInSpeaker),
        (.builtInReceiver, .builtInSpeaker),
        (.headphones, .wiredLineOut),
        (.lineOut, .wiredLineOut),
        (.usbAudio, .usbAudio),
        (.airPlay, .airPlay),
        (.bluetoothHFP, .other),
        (.bluetoothLE, .other),
        (.carAudio, .other)
    ])
    func portMapsToRouteKind(port: AVAudioSession.Port, expected: RouteKind) {
        #expect(OutputRouteMonitor.routeKind(for: port) == expected)
    }

    /// HFP must not be mistaken for A2DP. HFP is the bidirectional
    /// telephone profile: mono and narrowband. Classifying it as A2DP would
    /// let the app report healthy stereo playback while the room hears
    /// something far worse.
    @Test("Bluetooth HFP is not classified as A2DP")
    func hfpIsNotA2DP() {
        #expect(OutputRouteMonitor.routeKind(for: .bluetoothHFP) != .bluetoothA2DP)
    }

    @Test("Only built-in ports are internal", arguments: [
        (AVAudioSession.Port.builtInSpeaker, false),
        (.builtInReceiver, false),
        (.bluetoothA2DP, true),
        (.headphones, true),
        (.usbAudio, true),
        (.airPlay, true)
    ])
    func portExternality(port: AVAudioSession.Port, isExternal: Bool) {
        #expect(OutputRouteMonitor.isExternalPort(port) == isExternal)
    }

    /// Only the re-encoding wireless routes degrade quality. Marking a wired
    /// route as degraded would make the warning meaningless; failing to mark
    /// Bluetooth would let the app claim a bitrate the link discards (FR-014).
    @Test("Re-encoding routes are flagged as degrading", arguments: [
        (RouteKind.bluetoothA2DP, true),
        (.airPlay, true),
        (.wiredLineOut, false),
        (.usbAudio, false),
        (.builtInSpeaker, false),
        (.other, false)
    ])
    func qualityDegradation(kind: RouteKind, degrades: Bool) {
        #expect(OutputRouteMonitor.degradesQuality(kind: kind) == degrades)
    }

    /// Losing the speaker must be distinguishable from merely switching to
    /// another external route: only the former may fall back to the device's
    /// own speaker, which is what FR-018 exists to prevent.
    @Test("Built-in speaker is the only fallback that counts as output loss")
    func builtInSpeakerIsTheLossCase() {
        let externalPorts: [AVAudioSession.Port] = [.bluetoothA2DP, .headphones, .usbAudio, .airPlay]
        for port in externalPorts {
            #expect(OutputRouteMonitor.isExternalPort(port))
        }
        #expect(!OutputRouteMonitor.isExternalPort(.builtInSpeaker))
    }
}
