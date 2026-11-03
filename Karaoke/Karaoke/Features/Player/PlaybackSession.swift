// T055, T056, T061 — PlaybackSession.
//
// T055: In-memory state holder for one performance. Never persisted.
// T056: State machine per data-model.md:
//         idle → resolving → buffering → playing
//         resolving → failed (carrying which kind of failure)
//         stale address during playing → silent re-resolve (stays in playing)
// T061: Song.playCount and lastPlayedAt are incremented only when playback
//       passes the halfway point, not on selection.
//
// Satisfies: FR-005, FR-007, FR-008, FR-014, FR-017, FR-018, FR-019

import Foundation
import Observation
import SwiftData

// MARK: - SessionState

/// The state machine for a playback session (data-model.md PlaybackSession).
enum SessionState: Sendable, Equatable {
    case idle
    case resolving
    case buffering
    case playing
    case paused
    case interrupted
    case failed(PlaybackError)
    case finished
}

// MARK: - PlaybackError

/// A playback failure, carrying which kind it was (FR-008).
///
/// `resolving → failed` carries this so the UI can word it correctly:
/// an unavailable song is the singer's problem to route around;
/// a broken mechanism is the maintainer's.
enum PlaybackError: Sendable, Equatable {
    /// The song is unavailable (private, removed, region-blocked, etc.).
    /// Singer-facing: "This song is not available."
    case contentUnavailable(reason: String)
    /// The resolution mechanism is broken.
    /// Maintainer-facing: "The resolution mechanism needs updating."
    case mechanismFailed(detail: String)
    /// No network connection.
    case offline
    /// The audio format is not decodable on this device.
    case unsupportedFormat(codec: String, container: String)
    /// A generic audio error.
    case audioError(detail: String)

    static func from(sourceError: SourceError) -> PlaybackError {
        switch sourceError {
        case .notFound, .private_, .removed, .regionBlocked, .ageRestricted,
             .liveStreamUnsupported, .noAudioRenditions:
            return .contentUnavailable(reason: sourceError.singerFacingReason)
        case .offline:
            return .offline
        case .resolutionFailed, .upstreamContractChanged, .cipherFailure:
            return .mechanismFailed(detail: "Resolution mechanism error")
        default:
            return .mechanismFailed(detail: "Unexpected error")
        }
    }

    static func from(audioError: AudioError) -> PlaybackError {
        switch audioError {
        case .unsupportedFormat(let codec, let container):
            return .unsupportedFormat(codec: codec, container: container)
        case .sourceUnreadable(let detail):
            return .audioError(detail: detail)
        case .sessionConfigurationFailed(let detail):
            return .mechanismFailed(detail: detail)
        case .seekOutOfBounds(let requested, let duration):
            return .audioError(detail: "Seek \(requested) out of bounds [0, \(duration)]")
        case .noExternalOutput:
            return .contentUnavailable(reason: "No external speaker connected")
        }
    }
}

extension SourceError {
    var singerFacingReason: String {
        switch self {
        case .notFound(let id): return "Video \(id) not found"
        case .private_: return "This video is private"
        case .removed: return "This video has been removed"
        case .regionBlocked: return "This video is not available in your region"
        case .ageRestricted: return "This video requires age verification"
        case .liveStreamUnsupported: return "Live streams are not supported"
        case .noAudioRenditions: return "No playable audio format available"
        default: return "This video is not available"
        }
    }
}

// MARK: - PlaybackSession

/// Live state of one performance. In-memory only — never persisted.
///
/// Exists so every view reads one coherent description of what is happening.
/// The state machine is the single source of truth for what the player is doing.
///
/// `positionSeconds` is read from the audio clock, not accumulated from a timer
/// (audio-pipeline.md Behavioural requirement 1, data-model.md PlaybackSession).
@MainActor
@Observable
final class PlaybackSession {

    // MARK: Fields (data-model.md PlaybackSession)

    /// The song currently loaded. Null when idle.
    private(set) var songID: String?

    /// The selected rendition. What FR-005 reports.
    private(set) var selectedRendition: AudioRendition?

    /// Current position in seconds. Read from the audio clock.
    private(set) var positionSeconds: Double = 0

    /// Duration from the decoded asset. May differ from Song metadata; the
    /// decoded value wins for seek bounds (data-model.md).
    private(set) var durationSeconds: Double = 0

    /// The session state machine.
    private(set) var state: SessionState = .idle

    /// The active output route.
    private(set) var outputRoute: OutputRoute = .unknown

    /// The active route's output latency in milliseconds.
    /// Subtracted when placing lyrics (FR-019).
    private(set) var outputLatencyMs: Double = 0

    /// False means audio would play from the device's own speaker — the FR-018 pause trigger.
    private(set) var isExternalOutputPresent: Bool = false

    /// The last error. Cleared on successful state transition.
    private(set) var lastError: PlaybackError?

    /// Songs sung this session. The exclusion set for suggestions (FR-025c).
    /// Cleared when the session ends.
    private(set) var performedSongIDs: Set<String> = []

    // MARK: Dependencies

    private let pipeline: any AudioPipeline
    private let router: SourceProviderRouter
    private let addressCache: StreamAddressCache

    // MARK: Internal state

    /// Whether the halfway point has been passed for the current song (T061).
    private var halfwayReached: Bool = false

    /// The model context for updating Song.playCount and lastPlayedAt (T061).
    private var modelContext: ModelContext?

    // MARK: Event observation task

    private var eventTask: Task<Void, Never>?

    // MARK: Init

    init(
        pipeline: any AudioPipeline,
        router: SourceProviderRouter,
        addressCache: StreamAddressCache
    ) {
        self.pipeline = pipeline
        self.router = router
        self.addressCache = addressCache
        startObservingEvents()
    }

    // MARK: Session control

    /// Attach a model context for persisting play statistics (T061).
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Load and begin playing a song.
    ///
    /// Transitions: idle/failed → resolving → buffering → playing.
    func play(songID: String, rendition: AudioRendition) async {
        self.songID = songID
        self.selectedRendition = rendition
        self.halfwayReached = false
        transition(to: .resolving)

        do {
            // Resolve the stream address via the cache (FR-007).
            let address = try await addressCache.address(
                for: songID,
                itag: rendition.itag,
                provider: router
            )

            guard !Task.isCancelled else { return }

            transition(to: .buffering)

            try pipeline.prepare()
            try await pipeline.load(source: .remote(address))
            try pipeline.play()

            transition(to: .playing)
        } catch let sourceError as SourceError {
            transition(to: .failed(PlaybackError.from(sourceError: sourceError)))
        } catch let audioError as AudioError {
            transition(to: .failed(PlaybackError.from(audioError: audioError)))
        } catch {
            transition(to: .failed(.mechanismFailed(detail: error.localizedDescription)))
        }
    }

    /// Play a locally saved song (FR-030).
    func playLocal(songID: String, rendition: AudioRendition, url: URL) async {
        self.songID = songID
        self.selectedRendition = rendition
        self.halfwayReached = false
        transition(to: .resolving)

        do {
            transition(to: .buffering)
            try pipeline.prepare()
            try await pipeline.load(source: .local(url))
            try pipeline.play()
            transition(to: .playing)
        } catch {
            transition(to: .failed(.audioError(detail: error.localizedDescription)))
        }
    }

    func pause() {
        pipeline.pause()
        transition(to: .paused)
    }

    func resume() {
        do {
            try pipeline.play()
            transition(to: .playing)
        } catch {
            transition(to: .failed(.audioError(detail: error.localizedDescription)))
        }
    }

    func seek(to seconds: Double) async {
        do {
            try await pipeline.seek(to: seconds)
        } catch {
            lastError = .audioError(detail: error.localizedDescription)
        }
    }

    func setVolume(_ volume: Double) {
        pipeline.setVolume(volume)
    }

    func stop() {
        pipeline.stop()
        transition(to: .idle)
        songID = nil
        selectedRendition = nil
        positionSeconds = 0
        durationSeconds = 0
        halfwayReached = false
    }

    func endSession() {
        stop()
        performedSongIDs.removeAll()
    }

    // MARK: State machine

    private func transition(to newState: SessionState) {
        if case .failed = newState {
            lastError = {
                if case .failed(let error) = newState { return error }
                return nil
            }()
        } else {
            lastError = nil
        }
        state = newState
    }

    // MARK: Event observation

    private func startObservingEvents() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.pipeline.events {
                await self.handle(event: event)
            }
        }
    }

    private func handle(event: AudioPipelineEvent) async {
        switch event {
        case .positionUpdated(let pos):
            positionSeconds = pos.seconds
            checkHalfway(position: pos.seconds)

        case .stateChanged(let playbackState):
            switch playbackState {
            case .buffering:
                if case .resolving = state { transition(to: .buffering) }
            case .playing:
                if state != .playing { transition(to: .playing) }
            case .paused:
                if state != .paused { transition(to: .paused) }
            case .ended:
                markPerformed()
                transition(to: .finished)
            case .failed:
                transition(to: .failed(.audioError(detail: "Player failed")))
            case .idle, .loading:
                break
            }

        case .reachedEnd:
            markPerformed()
            transition(to: .finished)

        case .routeChanged(let route):
            outputRoute = route
            outputLatencyMs = route.outputLatencyMs
            isExternalOutputPresent = route.isExternal

        case .externalOutputLost(let previousKind):
            // FR-018: pause when external output is lost.
            isExternalOutputPresent = false
            outputRoute = OutputRoute(
                kind: .builtInSpeaker,
                isExternal: false,
                outputLatencyMs: 0,
                degradesQuality: false
            )
            outputLatencyMs = 0
            if state == .playing { transition(to: .paused) }
            DiagnosticLog.recordEnvironmentError(
                .offline,
                songID: songID ?? "unknown",
                providerID: SourceProviderID(rawValue: "PlaybackSession")
            )
            _ = previousKind // acknowledged

        case .externalOutputRestored(let route):
            isExternalOutputPresent = route.isExternal
            outputRoute = route
            outputLatencyMs = route.outputLatencyMs

        case .interrupted:
            if state == .playing { transition(to: .interrupted) }

        case .interruptionEnded:
            // Do NOT auto-resume (FR-016). Move to paused and let the UI offer resumption.
            if case .interrupted = state { transition(to: .paused) }

        case .stalled:
            // Stall does NOT trigger re-resolution (T051, audio-pipeline.md requirement 6).
            // Just update state to buffering if we were playing.
            if state == .playing { transition(to: .buffering) }

        case .error(let audioError):
            transition(to: .failed(PlaybackError.from(audioError: audioError)))
        }
    }

    // MARK: Halfway detection (T061)

    /// Check whether playback has passed the halfway point.
    ///
    /// `Song.playCount` and `lastPlayedAt` are incremented only when playback
    /// passes the halfway point, not on mere selection (data-model.md Song,
    /// T061). This prevents a song that is immediately skipped from counting
    /// as "played".
    private func checkHalfway(position: Double) {
        guard !halfwayReached, durationSeconds > 0 else { return }
        guard position >= durationSeconds / 2 else { return }
        halfwayReached = true
        if let id = songID {
            updatePlayStats(songID: id)
        }
    }

    private func markPerformed() {
        if let id = songID {
            performedSongIDs.insert(id)
        }
    }

    /// Increment `Song.playCount` and set `lastPlayedAt` in the SwiftData store.
    ///
    /// Called only when playback passes the halfway point (T061).
    private func updatePlayStats(songID: String) {
        guard let context = modelContext else { return }
        do {
            let targetID = songID
            let descriptor = FetchDescriptor<Song>(
                predicate: #Predicate { $0.id == targetID }
            )
            let songs = try context.fetch(descriptor)
            if let song = songs.first {
                song.playCount += 1
                song.lastPlayedAt = Date()
                try context.save()
            }
        } catch {
            DiagnosticLog.recordEnvironmentError(
                .offline,
                songID: songID,
                providerID: SourceProviderID(rawValue: "PlaybackSession")
            )
        }
    }

    // MARK: Silent re-resolve (T056, FR-007)

    /// Re-resolve a stale stream address without leaving the `playing` state.
    ///
    /// Called when the StreamAddressCache detects the address is stale during
    /// playback. The session stays in `playing` — the singer sees no interruption.
    func silentlyReResolve() async {
        guard let id = songID, let rendition = selectedRendition else { return }
        let savedPosition = positionSeconds

        do {
            // Invalidate the stale address and get a fresh one.
            await addressCache.invalidate(songID: id, itag: rendition.itag)
            let freshAddress = try await addressCache.address(
                for: id,
                itag: rendition.itag,
                provider: router
            )

            // Load the new address and seek to the saved position.
            try await pipeline.load(source: .remote(freshAddress))
            try pipeline.play()
            try await pipeline.seek(to: savedPosition)
            // State stays .playing — the singer sees nothing.
        } catch {
            // Re-resolve failed — now it is a real error.
            transition(to: .failed(.mechanismFailed(detail: "Re-resolve failed: \(error.localizedDescription)")))
        }
    }
}
