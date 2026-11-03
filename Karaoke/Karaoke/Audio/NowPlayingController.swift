// T129 — NowPlayingController.
//
// Wires MPNowPlayingInfoCenter and MPRemoteCommandCenter to the audio pipeline
// so the lock screen and Control Centre show track info and respond to transport
// controls (FR-015).
//
// Transport commands wired: play, pause, seek, next track.
// No previous-track command — the queue does not support going back.
//
// Satisfies: FR-015, SC-010

import Foundation
import MediaPlayer

// MARK: - NowPlayingController

/// Publishes track information to the system now-playing surface and wires
/// transport commands to the audio pipeline (FR-015).
///
/// Must be kept alive for the duration of a playback session. Call `invalidate()`
/// before releasing to deregister command handlers.
final class NowPlayingController: @unchecked Sendable {

    // MARK: Dependencies

    private let pipeline: any AudioPipeline
    private var nextTrackHandler: (@MainActor () -> Void)?

    // MARK: Command registrations

    private var playRegistration: Any?
    private var pauseRegistration: Any?
    private var seekRegistration: Any?
    private var nextRegistration: Any?

    // MARK: Init

    @MainActor
    init(pipeline: any AudioPipeline) {
        self.pipeline = pipeline
        registerCommands()
    }

    /// Deregister all command handlers and clear the now-playing surface.
    ///
    /// Call this before releasing the controller. Safe to call from any context.
    @MainActor
    func invalidate() {
        let center = MPRemoteCommandCenter.shared()
        if let r = playRegistration { center.playCommand.removeTarget(r) }
        if let r = pauseRegistration { center.pauseCommand.removeTarget(r) }
        if let r = seekRegistration { center.changePlaybackPositionCommand.removeTarget(r) }
        if let r = nextRegistration { center.nextTrackCommand.removeTarget(r) }
        playRegistration = nil
        pauseRegistration = nil
        seekRegistration = nil
        nextRegistration = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Public API

    @MainActor
    func update(
        title: String,
        channelName: String,
        durationSeconds: Double,
        positionSeconds: Double,
        isPlaying: Bool
    ) {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: channelName,
            MPMediaItemPropertyPlaybackDuration: durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    @MainActor
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    @MainActor
    func onNextTrack(_ handler: @escaping @MainActor () -> Void) {
        nextTrackHandler = handler
    }

    // MARK: Private — command registration

    @MainActor
    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        playRegistration = center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            do {
                try self.pipeline.play()
                return .success
            } catch {
                return .commandFailed
            }
        }

        pauseRegistration = center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.pipeline.pause()
            return .success
        }

        seekRegistration = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                try? await self?.pipeline.seek(to: seekEvent.positionTime)
            }
            return .success
        }

        nextRegistration = center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.nextTrackHandler?()
            return .success
        }

        center.previousTrackCommand.isEnabled = false
    }
}
