// T045 — AudioSource, PlaybackPosition, OutputRoute, RouteKind,
//         AudioPipelineEvent, AudioError.
//
// All types are value types (structs/enums) and Sendable so they cross actor
// boundaries safely. No microphone type, no pitch/tempo type — both absences
// are the contract (audio-pipeline.md Protocol).
//
// Satisfies: FR-009, FR-013, FR-014, FR-017 … FR-019

import Foundation

// MARK: - AudioSource

/// The source of audio for a playback session.
///
/// Both cases must produce identical output quality for the same rendition —
/// that is the substance of FR-030 (offline playback at online quality).
enum AudioSource: Sendable {
    /// A streaming rendition resolved to a time-limited URL (FR-003, FR-007).
    case remote(StreamAddress)
    /// A locally saved rendition (FR-030).
    case local(URL)
}

// MARK: - PlaybackPosition

/// The player's current position, read from the player's own clock.
///
/// No rate conversion field — playback rate is always 1.0 (FR-011), so the
/// position IS the source time. Nothing accumulates its own timer; that is how
/// lyric drift appears (audio-pipeline.md Behavioural requirement 1).
struct PlaybackPosition: Sendable, Equatable {
    /// Seconds from the start of the loaded asset.
    let seconds: Double
    /// False when nothing is loaded or the player is not yet ready.
    let isValid: Bool

    static let invalid = PlaybackPosition(seconds: 0, isValid: false)
}

// MARK: - RouteKind

/// The kind of audio output route currently active.
///
/// Used by `OutputRoute.degradesQuality` (FR-014) and by the external-output-lost
/// handler (FR-018). The distinction between re-encoding wireless routes and
/// direct routes is what makes FR-014 honest.
enum RouteKind: Sendable, Equatable, Hashable {
    /// Bluetooth A2DP — re-encodes audio; degrades quality (FR-014).
    case bluetoothA2DP
    /// The device's own built-in speaker.
    case builtInSpeaker
    /// Wired line output (3.5 mm or Lightning/USB-C adapter).
    case wiredLineOut
    /// USB audio device.
    case usbAudio
    /// AirPlay — re-encodes audio; degrades quality (FR-014).
    case airPlay
    /// Any other route not explicitly classified.
    case other
}

// MARK: - OutputRoute

/// The active audio output route and its characteristics.
///
/// `degradesQuality` is not decoration (audio-pipeline.md Session and route):
/// Bluetooth re-encodes the decoded audio before transmitting it. Since the
/// source is already lossy, that is a lossy-to-lossy transcode. The flag exists
/// so the app can be honest about audio quality it cannot deliver (FR-014).
///
/// `outputLatencyMs` drives the lyrics display (FR-019): the player reports
/// what has been dispatched; the speaker emits it later. The lyrics layer
/// subtracts this value. Read from the live route on every change — never
/// hardcoded (audio-pipeline.md Behavioural requirement 2).
struct OutputRoute: Sendable, Equatable {
    /// The kind of output device.
    let kind: RouteKind
    /// False when audio is playing from the device's own speaker (FR-018 trigger).
    let isExternal: Bool
    /// The route's output latency in milliseconds, read from AVAudioSession.outputLatency.
    /// Subtracted when placing lyrics so the display matches what the room hears (FR-019).
    let outputLatencyMs: Double
    /// True for any re-encoding wireless route (Bluetooth A2DP, AirPlay).
    /// Surfaced in QualityDetailView so the app does not advertise quality the link discards (FR-014).
    let degradesQuality: Bool

    /// A safe default used before the first route is observed.
    static let unknown = OutputRoute(
        kind: .other,
        isExternal: false,
        outputLatencyMs: 0,
        degradesQuality: false
    )
}

// MARK: - AudioPipelineEvent

/// Events emitted by the audio pipeline over its `events` stream.
///
/// Consumers observe this stream to drive UI and session state. The stream
/// never closes while the pipeline is alive.
enum AudioPipelineEvent: Sendable {
    /// The player's playback state changed (playing, paused, buffering, etc.).
    case stateChanged(PlaybackState)
    /// The player's position updated. Emitted at display-refresh cadence.
    case positionUpdated(PlaybackPosition)
    /// The current item played to its end.
    case reachedEnd
    /// The output route changed (FR-017). Does not pause playback unless the
    /// external route was lost.
    case routeChanged(OutputRoute)
    /// The external output route was lost (FR-018). The pipeline has already
    /// paused. Audio must not continue from the device's own speaker at party volume.
    case externalOutputLost(previous: RouteKind)
    /// The external output route was restored. The pipeline offers to resume
    /// from the paused position rather than restarting.
    case externalOutputRestored(OutputRoute)
    /// A system audio interruption began (FR-016). The pipeline has paused.
    case interrupted
    /// The interruption ended. `shouldResume` is the system's hint; the pipeline
    /// does NOT auto-resume — a call ending should not blast music mid-conversation.
    case interruptionEnded(shouldResume: Bool)
    /// The player stalled (buffering or link trouble).
    ///
    /// Deliberately NOT acted on by re-resolution — a radio problem is not a
    /// stream problem, and re-resolving makes it worse while spending quota
    /// (audio-pipeline.md Behavioural requirement 6, T051).
    case stalled
    /// A pipeline error occurred.
    case error(AudioError)
}

// MARK: - PlaybackState

/// The player's current playback state, carried by `stateChanged` events.
enum PlaybackState: Sendable, Equatable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case ended
    case failed
}

// MARK: - AudioError

/// Errors the audio pipeline can throw or emit.
///
/// `unsupportedFormat` triggers the Selection Rule's fallback to the next-best
/// playable rendition — the pipeline reports it rather than failing the song.
/// This is the case that matters most in practice: the highest-bitrate rendition
/// a source offers is frequently in a container the platform will not decode.
enum AudioError: Error, Sendable, Equatable {
    /// The audio session could not be configured.
    case sessionConfigurationFailed(detail: String)
    /// The loaded asset uses a format the device cannot decode.
    case unsupportedFormat(codec: String, container: String)
    /// The source URL is unreadable (network error, expired address, etc.).
    case sourceUnreadable(detail: String)
    /// A seek was requested outside the asset's duration (FR-023).
    ///
    /// Out-of-range seeks yield this error rather than clamping silently —
    /// silent clamping hides bugs in callers that compute positions incorrectly.
    case seekOutOfBounds(requested: Double, duration: Double)
    /// An operation requiring an external output was attempted with none connected.
    case noExternalOutput
}
