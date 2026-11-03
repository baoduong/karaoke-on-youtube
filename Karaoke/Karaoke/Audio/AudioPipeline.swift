// T044 — AudioPipeline protocol.
//
// The contract for the audio layer. Two absences are the contract:
//   • No microphone member (FR-010, SC-003).
//   • No pitch or tempo member (FR-011).
//
// Both are removed by scope decisions documented in audio-pipeline.md.
// Removing pitch and tempo removes the only reason this app needed an audio
// processing graph — nothing is left that AVPlayer does not already do better.
//
// Satisfies: FR-009 … FR-020

import Foundation

// MARK: - AudioPipeline

/// The audio layer contract.
///
/// Implementations use AVPlayer — no audio engine, no processing graph, no
/// render callbacks (audio-pipeline.md Architectural consequence).
///
/// **No microphone member.** The PA speaker owns the microphone in hardware.
/// Adding a microphone member here would be a contract violation (SC-003).
///
/// **No pitch or tempo member.** Songs play as published (FR-011). Adding
/// pitch or tempo processing would require an audio engine and a render thread,
/// which this design deliberately avoids.
protocol AudioPipeline: AnyObject, Sendable {

    // MARK: Lifecycle

    /// Configure the audio session for playback-only operation.
    ///
    /// Must be called before `load(source:)`. Configures `.playback` category
    /// on every code path — never `.playAndRecord`, which would prompt for
    /// microphone access and risk dropping Bluetooth to HFP mono (FR-010).
    func prepare() throws(AudioError)

    /// Tear down the pipeline and release all resources.
    func stop()

    // MARK: Playback (FR-009)

    /// Load an audio source and prepare it for playback.
    ///
    /// Both `.remote` and `.local` sources produce identical output quality
    /// for the same rendition (FR-030).
    func load(source: AudioSource) async throws(AudioError)

    /// Begin or resume playback.
    func play() throws(AudioError)

    /// Pause playback, retaining position.
    func pause()

    /// Seek to a position in seconds.
    ///
    /// - Throws: `AudioError.seekOutOfBounds` when `seconds` is outside the
    ///   asset's duration. Silent clamping is forbidden — it hides caller bugs.
    /// - Postcondition: Once this returns, `position` reflects the new value.
    ///   A dependent view must never observe the old position afterwards (FR-023).
    func seek(to seconds: Double) async throws(AudioError)

    /// The player's current position.
    ///
    /// Single source of truth for playback position, read from the player's own
    /// clock. Never a wall-clock timer, never an accumulated counter — that is
    /// how lyric drift appears (audio-pipeline.md Behavioural requirement 1).
    var position: PlaybackPosition { get }

    /// Total length of the loaded item, or 0 while unknown.
    ///
    /// For HLS this arrives asynchronously after the manifest is parsed, so
    /// callers must read it repeatedly rather than once at load time.
    var duration: Double { get }

    // MARK: Level only (FR-013)

    /// Set the output volume.
    ///
    /// - Parameter volume: Clamped to 0…1 before reaching the player.
    ///   Changes are ramped so no audible click occurs and take effect within
    ///   200 ms (SC-007). No other processing is applied to the samples (FR-009).
    func setVolume(_ volume: Double)

    // MARK: Tone control (FR-043)

    /// Apply the singer's tone control. Safe to call during playback.
    ///
    /// Takes effect within 200 ms with no click (SC-015). Flat or bypassed
    /// settings leave the samples untouched, which is what keeps SC-007's
    /// bit-identity claim true by default.
    func setEqualizer(_ settings: EqualizerSettings)

    /// False when the platform cannot apply a tone control to what is
    /// currently loaded, so the UI can say why instead of showing a control
    /// that silently does nothing (Principle VI) — which is exactly how
    /// `AVPlayer` behaves with an audio mix on HLS before iOS 27.
    var isEqualizerAvailable: Bool { get }

    // MARK: Output route (FR-014, FR-017 … FR-019)

    /// The currently active output route.
    ///
    /// Updated whenever the route changes. `outputLatencyMs` is read from the
    /// live route on every change — never hardcoded (audio-pipeline.md
    /// Behavioural requirement 2).
    var outputRoute: OutputRoute { get }

    /// An async stream of pipeline events.
    ///
    /// The stream never closes while the pipeline is alive. Consumers drive UI
    /// and session state from this stream.
    var events: AsyncStream<AudioPipelineEvent> { get }
}
