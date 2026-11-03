// T049 — OutputRouteMonitor.
//
// Monitors the AVAudioSession output route and publishes changes.
//
// Key design decisions:
//   • `outputLatencyMs` is read from AVAudioSession.outputLatency on every
//     route change — never hardcoded (audio-pipeline.md Behavioural requirement 2,
//     FR-019). The system's reported latency is frequently inaccurate for
//     third-party wireless speakers, which is why FR-020 provides a manual trim
//     layered on top.
//   • `degradesQuality` is true for Bluetooth A2DP and AirPlay — both re-encode
//     the decoded audio before transmitting it (FR-014, audio-pipeline.md).
//   • When the external route is lost, `onExternalOutputLost` fires BEFORE
//     `onRouteChange` so the pipeline can pause before the route update propagates.
//
// AVFoundation APIs used:
//   • Route change detection: AVAudioSession.routeChangeNotification
//   • Latency: AVAudioSession.outputLatency (seconds, converted to ms)
//   • Route description: AVAudioSession.currentRoute.outputs[].portType
//
// Satisfies: FR-014, FR-017, FR-018, FR-019

import AVFoundation

// MARK: - OutputRouteMonitor

/// Monitors the active audio output route and fires callbacks on changes.
///
/// `outputLatencyMs` is read from the live route on every change — never
/// hardcoded — because the system's reported latency is the only value we have
/// and FR-020 provides a manual trim for when it is wrong (FR-019).
final class OutputRouteMonitor: @unchecked Sendable {

    // MARK: Callbacks

    /// Called when the route changes (but the external output was not lost).
    var onRouteChange: ((OutputRoute) -> Void)?

    /// Called when the external output route is lost (FR-018).
    /// The pipeline must pause before this returns.
    var onExternalOutputLost: ((RouteKind) -> Void)?

    /// Called when an external output route is restored after being lost.
    var onExternalOutputRestored: ((OutputRoute) -> Void)?

    // MARK: State

    private var previousRoute: OutputRoute = .unknown
    private var wasExternallyRouted = false

    // MARK: Monitoring

    func startMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeDidChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        // Capture the initial route.
        previousRoute = currentOutputRoute()
        wasExternallyRouted = previousRoute.isExternal
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }

    // MARK: Current route

    /// Build an OutputRoute from the current AVAudioSession state.
    ///
    /// `outputLatencyMs` is read from `AVAudioSession.outputLatency` — the live
    /// value for the current route. This is the only source of truth for latency;
    /// no constant is used (audio-pipeline.md Behavioural requirement 2).
    func currentOutputRoute() -> OutputRoute {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let latencyMs = session.outputLatency * 1000

        guard let firstOutput = outputs.first else {
            return OutputRoute(
                kind: .other,
                isExternal: false,
                outputLatencyMs: latencyMs,
                degradesQuality: false
            )
        }

        let kind = routeKind(for: firstOutput.portType)
        let isExternal = isExternalPort(firstOutput.portType)
        let degrades = degradesQuality(kind: kind)

        return OutputRoute(
            kind: kind,
            isExternal: isExternal,
            outputLatencyMs: latencyMs,
            degradesQuality: degrades
        )
    }

    // MARK: Route change handler

    @objc private func routeDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        let newRoute = currentOutputRoute()

        switch reason {
        case .oldDeviceUnavailable:
            // An output device was disconnected (e.g., Bluetooth speaker dropped).
            // If we were on an external route, this is the FR-018 trigger.
            if wasExternallyRouted && !newRoute.isExternal {
                // Capture the previous kind before updating state.
                let previousKind = previousRoute.kind
                previousRoute = newRoute
                wasExternallyRouted = false
                // Fire lost BEFORE routeChange so the pipeline can pause first.
                onExternalOutputLost?(previousKind)
            } else {
                previousRoute = newRoute
                wasExternallyRouted = newRoute.isExternal
                onRouteChange?(newRoute)
            }

        case .newDeviceAvailable:
            // A new output device connected (e.g., Bluetooth speaker reconnected).
            let wasExternal = wasExternallyRouted
            previousRoute = newRoute
            wasExternallyRouted = newRoute.isExternal
            if !wasExternal && newRoute.isExternal {
                // Restored from built-in to external.
                onExternalOutputRestored?(newRoute)
            } else {
                onRouteChange?(newRoute)
            }

        case .override, .wakeFromSleep, .noSuitableRouteForCategory,
             .routeConfigurationChange, .categoryChange, .unknown:
            previousRoute = newRoute
            wasExternallyRouted = newRoute.isExternal
            onRouteChange?(newRoute)

        @unknown default:
            previousRoute = newRoute
            wasExternallyRouted = newRoute.isExternal
            onRouteChange?(newRoute)
        }
    }

    // MARK: Classification helpers

    /// Map an AVAudioSession port type to a RouteKind.
    ///
    /// The classification determines `degradesQuality` and `isExternal`.
    /// Route classification is tested by T064 (OutputRouteTests).
    static func routeKind(for portType: AVAudioSession.Port) -> RouteKind {
        switch portType {
        case .bluetoothA2DP:
            return .bluetoothA2DP
        case .builtInSpeaker, .builtInReceiver:
            return .builtInSpeaker
        case .headphones, .lineOut:
            return .wiredLineOut
        case .usbAudio:
            return .usbAudio
        case .airPlay:
            return .airPlay
        case .bluetoothHFP, .bluetoothLE:
            // HFP is telephone-quality mono — classify as other so the UI
            // can warn the singer. Not the same as A2DP.
            return .other
        default:
            return .other
        }
    }

    /// Whether a port type represents an external (non-device) output.
    static func isExternalPort(_ portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .builtInSpeaker, .builtInReceiver:
            return false
        default:
            return true
        }
    }

    /// Whether a route kind re-encodes the audio (FR-014).
    ///
    /// Bluetooth A2DP and AirPlay both re-encode the decoded audio before
    /// transmitting it. Since the source is already lossy, this is a
    /// lossy-to-lossy transcode — the narrowest point in the chain.
    static func degradesQuality(kind: RouteKind) -> Bool {
        switch kind {
        case .bluetoothA2DP, .airPlay:
            return true
        case .builtInSpeaker, .wiredLineOut, .usbAudio, .other:
            return false
        }
    }

    // MARK: Private helpers (instance wrappers for static methods)

    private func routeKind(for portType: AVAudioSession.Port) -> RouteKind {
        Self.routeKind(for: portType)
    }

    private func isExternalPort(_ portType: AVAudioSession.Port) -> Bool {
        Self.isExternalPort(portType)
    }

    private func degradesQuality(kind: RouteKind) -> Bool {
        Self.degradesQuality(kind: kind)
    }
}
