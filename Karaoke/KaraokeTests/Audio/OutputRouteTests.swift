// T064 — Route classification tests.
//
// Maps a table of route descriptors to the correct kind, isExternal,
// degradesQuality, and delay.
//
// Satisfies: FR-014, FR-017, FR-018, FR-019

import Testing
import AVFoundation
@testable import Karaoke

@Suite("Output route classification")
struct OutputRouteTests {

    // MARK: RouteKind classification

    @Test("Bluetooth A2DP port maps to .bluetoothA2DP")
    func bluetoothA2DPKind() {
        let kind = OutputRouteMonitor.routeKind(for: .bluetoothA2DP)
        #expect(kind == .bluetoothA2DP)
    }

    @Test("Built-in speaker port maps to .builtInSpeaker")
    func builtInSpeakerKind() {
        let kind = OutputRouteMonitor.routeKind(for: .builtInSpeaker)
        #expect(kind == .builtInSpeaker)
    }

    @Test("Built-in receiver port maps to .builtInSpeaker")
    func builtInReceiverKind() {
        let kind = OutputRouteMonitor.routeKind(for: .builtInReceiver)
        #expect(kind == .builtInSpeaker)
    }

    @Test("Headphones port maps to .wiredLineOut")
    func headphonesKind() {
        let kind = OutputRouteMonitor.routeKind(for: .headphones)
        #expect(kind == .wiredLineOut)
    }

    @Test("Line out port maps to .wiredLineOut")
    func lineOutKind() {
        let kind = OutputRouteMonitor.routeKind(for: .lineOut)
        #expect(kind == .wiredLineOut)
    }

    @Test("USB audio port maps to .usbAudio")
    func usbAudioKind() {
        let kind = OutputRouteMonitor.routeKind(for: .usbAudio)
        #expect(kind == .usbAudio)
    }

    @Test("AirPlay port maps to .airPlay")
    func airPlayKind() {
        let kind = OutputRouteMonitor.routeKind(for: .airPlay)
        #expect(kind == .airPlay)
    }

    @Test("Bluetooth HFP port maps to .other (not A2DP)")
    func bluetoothHFPKind() {
        // HFP is telephone-quality mono — not the same as A2DP.
        let kind = OutputRouteMonitor.routeKind(for: .bluetoothHFP)
        #expect(kind == .other)
    }

    // MARK: isExternal classification

    @Test("Built-in speaker is not external")
    func builtInSpeakerNotExternal() {
        #expect(OutputRouteMonitor.isExternalPort(.builtInSpeaker) == false)
    }

    @Test("Built-in receiver is not external")
    func builtInReceiverNotExternal() {
        #expect(OutputRouteMonitor.isExternalPort(.builtInReceiver) == false)
    }

    @Test("Bluetooth A2DP is external")
    func bluetoothA2DPIsExternal() {
        #expect(OutputRouteMonitor.isExternalPort(.bluetoothA2DP) == true)
    }

    @Test("Headphones are external")
    func headphonesAreExternal() {
        #expect(OutputRouteMonitor.isExternalPort(.headphones) == true)
    }

    @Test("AirPlay is external")
    func airPlayIsExternal() {
        #expect(OutputRouteMonitor.isExternalPort(.airPlay) == true)
    }

    // MARK: degradesQuality classification (FR-014)

    @Test("Bluetooth A2DP degrades quality")
    func bluetoothA2DPDegrades() {
        #expect(OutputRouteMonitor.degradesQuality(kind: .bluetoothA2DP) == true)
    }

    @Test("AirPlay degrades quality")
    func airPlayDegrades() {
        #expect(OutputRouteMonitor.degradesQuality(kind: .airPlay) == true)
    }

    @Test("Built-in speaker does not degrade quality")
    func builtInSpeakerNoDegradation() {
        #expect(OutputRouteMonitor.degradesQuality(kind: .builtInSpeaker) == false)
    }

    @Test("Wired line out does not degrade quality")
    func wiredLineOutNoDegradation() {
        #expect(OutputRouteMonitor.degradesQuality(kind: .wiredLineOut) == false)
    }

    @Test("USB audio does not degrade quality")
    func usbAudioNoDegradation() {
        #expect(OutputRouteMonitor.degradesQuality(kind: .usbAudio) == false)
    }

    // MARK: OutputRoute struct

    @Test("OutputRoute.unknown has isExternal false")
    func unknownRouteNotExternal() {
        #expect(OutputRoute.unknown.isExternal == false)
    }

    @Test("OutputRoute.unknown has degradesQuality false")
    func unknownRouteNoDegradation() {
        #expect(OutputRoute.unknown.degradesQuality == false)
    }

    @Test("OutputRoute.unknown has outputLatencyMs 0")
    func unknownRouteZeroLatency() {
        #expect(OutputRoute.unknown.outputLatencyMs == 0)
    }
}
