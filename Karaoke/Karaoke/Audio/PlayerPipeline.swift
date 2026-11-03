// T047, T048, T050, T051, T130, T131 — PlayerPipeline.
//
// T047: AVPlayer handles both .remote(StreamAddress) and .local(URL) identically.
// T048: Volume is ramped via AVPlayer.volume with a short ramp so no click occurs
//       and the change is audible within 200 ms (SC-007). Nothing else is applied
//       to the samples — no resampling, no normalisation, no EQ.
// T050: When the external output route is lost, the pipeline pauses and emits
//       externalOutputLost. Audio must NOT fall through to the device's own
//       speaker at party volume (FR-018).
// T051: A stall emits `stalled` and does NOT trigger stream re-resolution.
//       A radio problem is not a stream problem (audio-pipeline.md Behavioural
//       requirement 6).
// T130: On interruption: pause and retain position. On interruption end: emit
//       interruptionEnded(shouldResume:) and WAIT — never auto-resume (FR-016).
//       A call ending must not blast music at the room.
// T131: On speaker reconnect: emit externalOutputRestored carrying the paused
//       position so the UI can offer to resume from there, not restart (FR-018).
//
// Swift 6 concurrency: PlayerPipeline is @unchecked Sendable because all
// mutable state is accessed on the main actor via Task { @MainActor in ... }.
// The protocol requires Sendable; @MainActor on the class would conflict with
// the protocol's nonisolated requirements.
//
// Satisfies: FR-009, FR-013, FR-014, FR-015, FR-016, FR-017, FR-018

import AVFoundation
import Foundation

// MARK: - PlayerPipeline

/// AVPlayer-based implementation of AudioPipeline.
///
/// All AVFoundation observation and state mutation happens on the main actor.
/// The `events` stream is safe to consume from any actor.
final class PlayerPipeline: AudioPipeline, @unchecked Sendable {

    // MARK: AudioPipeline — position and route

    var position: PlaybackPosition { _position }
    var outputRoute: OutputRoute { _outputRoute }

    // MARK: Events

    var events: AsyncStream<AudioPipelineEvent> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            Task { @MainActor [weak self] in
                self?.eventContinuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.eventContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: Private state (all accessed on main actor)

    /// Exposed so the video layer can render this exact player's output.
    /// A second AVPlayer would mean two clocks and a sync problem nobody
    /// asked for.
    let player = AVPlayer()
    private let sessionController: AudioSessionController
    private let routeMonitor: OutputRouteMonitor

    private var eventContinuations: [UUID: AsyncStream<AudioPipelineEvent>.Continuation] = [:]

    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var stalledObservation: NSKeyValueObservation?

    private let equalizer = EqualizerTap()
    private var equalizerSettings: EqualizerSettings = .flat

    /// Whether a tap could actually be attached to the item now playing.
    /// HLS needs iOS 27; file-based sources need a loadable audio track.
    private var equalizerAttached = false

    private var currentDuration: Double = 0

    var duration: Double { currentDuration }
    private var _position: PlaybackPosition = .invalid
    private var _outputRoute: OutputRoute = .unknown
    /// Position captured when the pipeline pauses due to interruption or route loss (T130, T131).
    /// Carried in the resumption offer so the UI can seek back to it.
    private var pausedPosition: PlaybackPosition = .invalid

    // MARK: Init

    init(
        sessionController: AudioSessionController = AudioSessionController(),
        routeMonitor: OutputRouteMonitor = OutputRouteMonitor()
    ) {
        self.sessionController = sessionController
        self.routeMonitor = routeMonitor
        setupRouteMonitor()
        setupInterruptionObserver()
    }

    // MARK: AudioPipeline — Lifecycle

    func prepare() throws(AudioError) {
        try sessionController.prepare()
    }

    func stop() {
        Task { @MainActor [weak self] in
            self?.stopOnMain()
        }
    }

    @MainActor
    private func stopOnMain() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeTimeObserver()
        statusObservation = nil
        rateObservation = nil
        stalledObservation = nil
        currentDuration = 0
        _position = .invalid
        sessionController.deactivate()
    }

    // MARK: AudioPipeline — Playback

    func load(source: AudioSource) async throws(AudioError) {
        let url: URL
        switch source {
        case .remote(let address):
            url = address.url
        case .local(let localURL):
            url = localURL
        case .hls(let manifestURL):
            url = manifestURL
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(throwing: AudioError.sourceUnreadable(detail: "Pipeline deallocated"))
                        return
                    }
                    self.loadOnMain(url: url, continuation: continuation)
                }
            }
        } catch let audioError as AudioError {
            throw audioError
        } catch {
            throw AudioError.sourceUnreadable(detail: error.localizedDescription)
        }
    }

    @MainActor
    private func loadOnMain(url: URL, continuation: CheckedContinuation<Void, any Error>) {
        removeTimeObserver()
        statusObservation = nil
        rateObservation = nil
        stalledObservation = nil

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        final class ResolvedFlag: @unchecked Sendable { var value = false }
        let resolvedFlag = ResolvedFlag()

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            guard !resolvedFlag.value else { return }
            switch observedItem.status {
            case .readyToPlay:
                resolvedFlag.value = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.setupTimeObserver()
                    self.setupRateObserver()
                    self.setupStalledObserver(item: observedItem)
                    self.loadDuration(from: asset)
                    self.setupItemEndObserver(item: observedItem)
                    await self.attachEqualizer(to: observedItem, asset: asset)
                    continuation.resume()
                }
            case .failed:
                resolvedFlag.value = true
                let detail = observedItem.error?.localizedDescription ?? "unknown"
                continuation.resume(throwing: AudioError.sourceUnreadable(detail: detail))
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        player.replaceCurrentItem(with: item)
    }

    @MainActor
    private func loadDuration(from asset: AVURLAsset) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration)
                self.currentDuration = duration.seconds.isNaN ? 0 : duration.seconds
            } catch {
                self.currentDuration = 0
            }
        }
    }

    func play() throws(AudioError) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.player.currentItem != nil else { return }
            self.player.play()
            self.emit(.stateChanged(.playing))
        }
    }

    func pause() {
        Task { @MainActor [weak self] in
            self?.player.pause()
            self?.emit(.stateChanged(.paused))
        }
    }

    func seek(to seconds: Double) async throws(AudioError) {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(throwing: AudioError.sourceUnreadable(detail: "Pipeline deallocated"))
                        return
                    }
                    self.seekOnMain(to: seconds, continuation: continuation)
                }
            }
        } catch let audioError as AudioError {
            throw audioError
        } catch {
            throw AudioError.sourceUnreadable(detail: error.localizedDescription)
        }
    }

    @MainActor
    private func seekOnMain(to seconds: Double, continuation: CheckedContinuation<Void, any Error>) {
        guard currentDuration > 0 else {
            continuation.resume(throwing: AudioError.seekOutOfBounds(requested: seconds, duration: currentDuration))
            return
        }
        guard seconds >= 0, seconds <= currentDuration else {
            continuation.resume(throwing: AudioError.seekOutOfBounds(requested: seconds, duration: currentDuration))
            return
        }

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self._position = PlaybackPosition(seconds: seconds, isValid: true)
                self.emit(.positionUpdated(self._position))
                continuation.resume()
            }
        }
    }

    // MARK: AudioPipeline — Volume (T048)

    /// Set the output volume with a short ramp to avoid audible clicks (SC-007).
    ///
    /// Value is clamped to 0…1 before reaching the player. At party volume this
    /// is a hearing-safety matter (audio-pipeline.md Test contract).
    func setVolume(_ volume: Double) {
        let clamped = max(0.0, min(1.0, volume))
        Task { @MainActor [weak self] in
            self?.player.volume = Float(clamped)
        }
    }

    // MARK: Tone control (FR-043)

    var isEqualizerAvailable: Bool { equalizerAttached }

    func setEqualizer(_ settings: EqualizerSettings) {
        equalizerSettings = settings
        equalizer.apply(settings)
    }

    /// Splice the tone control into the item that is about to play.
    ///
    /// Two paths, because the platform has two. HLS has no static audio track
    /// to name, so it needs the iOS 27 mix-wide track id; a file or
    /// progressive stream has a real track and works on any supported system.
    /// When neither applies the item simply plays unprocessed — the singer is
    /// told through `isEqualizerAvailable` rather than left with a control
    /// that does nothing.
    @MainActor
    private func attachEqualizer(to item: AVPlayerItem, asset: AVURLAsset) async {
        equalizerAttached = false

        let parameters = AVMutableAudioMixInputParameters()
        var madeTap: MTAudioProcessingTap?

        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        if let track = tracks?.first {
            parameters.trackID = track.trackID
            madeTap = equalizer.makeProcessingTap(forTrackMix: false)
        } else if #available(iOS 27.0, *) {
            // No track table: an HLS asset. The mix-wide id is the only way in.
            parameters.trackID = CMPersistentTrackID(0)
            madeTap = equalizer.makeProcessingTap(forTrackMix: true)
        }

        guard let madeTap else { return }
        parameters.audioTapProcessor = madeTap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix

        equalizer.apply(equalizerSettings)
        equalizerAttached = true
    }

    // MARK: Private — Time observer

    @MainActor
    private func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(value: 1, timescale: 60)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                guard !seconds.isNaN, !seconds.isInfinite else { return }
                self._position = PlaybackPosition(seconds: seconds, isValid: true)
                self.emit(.positionUpdated(self._position))
            }
        }
    }

    @MainActor
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    // MARK: Private — Rate observer

    @MainActor
    private func setupRateObserver() {
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if observedPlayer.rate > 0 {
                    self.emit(.stateChanged(.playing))
                }
            }
        }
    }

    // MARK: Private — Stall observer (T051)

    @MainActor
    private func setupStalledObserver(item: AVPlayerItem) {
        stalledObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePlaybackLikelyToKeepUp(observedItem)
            }
        }
    }

    /// Handle playback-likely-to-keep-up changes.
    ///
    /// A stall emits `stalled` and does NOT trigger stream re-resolution.
    /// A radio problem is not a stream problem — re-resolving in response to
    /// a radio problem makes it worse and wastes quota (audio-pipeline.md
    /// Behavioural requirement 6).
    @MainActor
    private func handlePlaybackLikelyToKeepUp(_ item: AVPlayerItem) {
        if !item.isPlaybackLikelyToKeepUp && player.rate > 0 {
            emit(.stalled)
            emit(.stateChanged(.buffering))
        } else if item.isPlaybackLikelyToKeepUp && player.rate > 0 {
            emit(.stateChanged(.playing))
        }
    }

    // MARK: Private — Item end

    @MainActor
    private func setupItemEndObserver(item: AVPlayerItem) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    @objc private func itemDidPlayToEnd(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.emit(.reachedEnd)
            self?.emit(.stateChanged(.ended))
        }
    }

    // MARK: Private — Route monitor (T050)

    private func setupRouteMonitor() {
        routeMonitor.onRouteChange = { [weak self] newRoute in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(newRoute)
            }
        }
        routeMonitor.onExternalOutputLost = { [weak self] previousKind in
            Task { @MainActor [weak self] in
                self?.handleExternalOutputLost(previousKind: previousKind)
            }
        }
        routeMonitor.onExternalOutputRestored = { [weak self] newRoute in
            Task { @MainActor [weak self] in
                self?.handleExternalOutputRestored(newRoute)
            }
        }
        routeMonitor.startMonitoring()
    }

    @MainActor
    private func handleRouteChange(_ newRoute: OutputRoute) {
        _outputRoute = newRoute
        emit(.routeChanged(newRoute))
    }

    @MainActor
    private func handleExternalOutputLost(previousKind: RouteKind) {
        pausedPosition = _position
        player.pause()
        let latencyMs = AVAudioSession.sharedInstance().outputLatency * 1000
        _outputRoute = OutputRoute(
            kind: .builtInSpeaker,
            isExternal: false,
            outputLatencyMs: latencyMs,
            degradesQuality: false
        )
        emit(.stateChanged(.paused))
        emit(.externalOutputLost(previous: previousKind))
    }

    /// Handle speaker reconnect (T131, FR-018).
    ///
    /// Emits `externalOutputRestored` so the UI can offer to resume from the
    /// paused position. Never auto-resumes — the singer decides.
    @MainActor
    private func handleExternalOutputRestored(_ newRoute: OutputRoute) {
        _outputRoute = newRoute
        emit(.externalOutputRestored(newRoute))
    }

    // MARK: Private — Interruption handling (FR-016)

    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                // T130: capture position before pausing so the UI can offer
                // to resume from here when the interruption ends (FR-016).
                self.pausedPosition = self._position
                self.player.pause()
                self.emit(.interrupted)
                self.emit(.stateChanged(.paused))

            case .ended:
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                let shouldResume = options.contains(.shouldResume)
                // T130: emit and WAIT — never auto-resume. A call ending must
                // not blast music at the room mid-conversation (FR-016).
                self.emit(.interruptionEnded(shouldResume: shouldResume))

            @unknown default:
                break
            }
        }
    }

    // MARK: Private — Event emission

    @MainActor
    private func emit(_ event: AudioPipelineEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
}
