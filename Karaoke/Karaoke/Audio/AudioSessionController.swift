// T046 — AudioSessionController.
//
// Configures the AVAudioSession for playback-only operation.
//
// INVARIANT: The session category is ALWAYS .playback. There is no code path
// that configures .playAndRecord. This is enforced by:
//   1. This file containing only one call to setCategory, with .playback.
//   2. The SwiftLint custom rule `no_microphone_api` that errors on .playAndRecord.
//   3. T062 (AudioSessionControllerTests) that verifies the category on every
//      path through `prepare`.
//
// Why .playback matters:
//   - .playAndRecord would prompt for microphone access (FR-010 violation).
//   - .playAndRecord can force Bluetooth to HFP profile, which is telephone-quality
//     mono — catastrophic for a karaoke app (audio-pipeline.md Session and route).
//
// Satisfies: FR-010, FR-015, FR-016

import AVFoundation

// MARK: - AudioSessionController

/// Configures and activates the AVAudioSession for playback-only operation.
///
/// This is the only place in the app that touches AVAudioSession. Centralising
/// it here makes T062's session-category test exhaustive: if every path through
/// `prepare` is covered, the invariant holds as the code changes.
final class AudioSessionController: Sendable {

    // MARK: Public API

    /// Configure the audio session for playback.
    ///
    /// Sets category to `.playback` with `.defaultToSpeaker` option so audio
    /// routes correctly when no external device is connected. Activates the
    /// session so it is ready before `load(source:)` is called.
    ///
    /// - Throws: `AudioError.sessionConfigurationFailed` if the OS rejects the
    ///   configuration. This is rare but possible (e.g., another app holds an
    ///   exclusive session).
    ///
    /// **No conditional that could configure .playAndRecord.** The category is
    /// `.playback` on every code path. T062 verifies this.
    func prepare() throws(AudioError) {
        let session = AVAudioSession.sharedInstance()
        do {
            // Category: .playback — the only category used in this app.
            // Mode: .default — no voice processing, no measurement mode.
            // Options: .defaultToSpeaker so audio plays from the speaker when
            //          no external route is connected (not silent through earpiece).
            //          .allowBluetooth is NOT set — we use .allowBluetoothA2DP
            //          which keeps the A2DP profile and avoids HFP downgrade.
            //          .allowBluetoothA2DP is implied by .playback category.
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            throw AudioError.sessionConfigurationFailed(detail: error.localizedDescription)
        }
    }

    /// Deactivate the audio session, allowing other apps to resume.
    ///
    /// Called from `PlayerPipeline.stop()`. Uses `.notifyOthersOnDeactivation`
    /// so music apps that were interrupted can resume (FR-016 courtesy).
    func deactivate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            DiagnosticLog.recordEnvironmentError(
                .offline,
                songID: "session",
                providerID: SourceProviderID(rawValue: "AudioSessionController")
            )
        }
    }

    /// The current session category. Used by T062 to verify the invariant.
    var currentCategory: AVAudioSession.Category {
        AVAudioSession.sharedInstance().category
    }
}
