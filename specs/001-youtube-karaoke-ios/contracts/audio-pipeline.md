# Contract: AudioPipeline

**Feature**: `001-youtube-karaoke-ios` | **Phase**: 1 (Design)

**Satisfies**: FR-009 … FR-020

## Scope: play the file, change nothing

Two scope decisions have collapsed this layer to almost nothing, and that is the headline of this contract:

1. **No microphone.** The PA speaker owns the microphone, its preamp, its effects, and the vocal-versus-music mix, all in hardware.
2. **No pitch or tempo processing.** Songs play as published. The app picks the best rendition rather than trying to improve a lesser one.

What remains is: decode a stream, apply level, send it out, report the position accurately, and survive a Bluetooth link.

| Removed by scope | Consequence |
|---|---|
| Microphone capture and permission | No record-capable session; no privacy string |
| Live monitoring, round-trip latency budget | Nothing is monitored through the device |
| Acoustic feedback suppression | The speaker's own circuitry handles it |
| Vocal effects, vocal/music balance | Hardware controls on the speaker |
| Pitch shifting, tempo stretching | **No audio-processing graph at all** |
| Custom render callbacks | **No real-time-safety hazard remains** |

### Architectural consequence: no audio engine, no render thread

Removing pitch and tempo removes the only reason this app needed an audio processing graph. Nothing is left that a standard system media player does not already do better:

- streaming an HTTP audio asset with range requests and buffering
- decoding whatever container the platform supports
- continuing in the background and on the lock screen
- publishing to the now-playing surface and accepting transport commands
- reporting playback position and surviving route changes
- applying a simple output volume

**Implementation decision: use the platform's standard media player, not a custom audio engine.** This is the single largest simplification available in the project. Writing a render-callback graph to do what the system player already does would add a real-time hazard, a buffering implementation, and a background-audio integration, in exchange for nothing the singer can hear.

**Constitution note.** Principle I ("The Audio Path Is Sacred") was written for a design that owned a render thread. This design owns none. The principle is not violated — it is unreachable, because the forbidden operations all concern code inside render callbacks and no such callback exists. Should a future change reintroduce a processing graph, Principle I applies again in full and this section must be revisited. Recorded here rather than amended away, per the constitution's governance rule.

### The obligation that replaced it

Bluetooth is the only supported route. It delays the audio behind the screen by enough to desynchronise the words, and it re-encodes the audio. The pipeline's remaining non-trivial job is to **measure and publish that delay** (FR-019) and to **report that the route degrades quality** (FR-014), honestly.

## Protocol

```swift
protocol AudioPipeline: AnyObject {
    // ── Lifecycle ────────────────────────────────────────────────
    func prepare() throws(AudioError)      // playback-only session
    func stop()

    // ── Playback (FR-009) ────────────────────────────────────────
    func load(source: AudioSource) async throws(AudioError)
    func play() throws(AudioError)
    func pause()
    func seek(to seconds: Double) async throws(AudioError)

    /// Single source of truth for playback position, read from the player's
    /// own clock. Never a wall-clock timer, never an accumulated counter.
    var position: PlaybackPosition { get }

    // ── Level only (FR-013) ──────────────────────────────────────
    func setVolume(_ volume: Double)        // 0...1, ramped

    // ── Output route (FR-014, FR-017 … FR-019) ───────────────────
    var outputRoute: OutputRoute { get }

    var events: AsyncStream<AudioPipelineEvent> { get }
}
```

No microphone member, and no pitch or tempo member. Both absences are the contract. SC-003 verifies the first by confirming no permission prompt ever appears; SC-007's bit-identity check verifies the second by confirming the output is the decoded source with level applied and nothing else.

### AudioSource

```swift
enum AudioSource {
    case remote(StreamAddress)      // streaming playback
    case local(URL)                 // SavedSong, FR-030
}
```

Both paths must produce identical output for the same rendition — that is the substance of FR-030.

### Position

```swift
struct PlaybackPosition {
    let seconds: Double
    let isValid: Bool      // false when nothing is loaded or ready
}
```

No rate conversion field. Playback rate is always 1.0 (FR-011), so the position *is* the source time. The struct that previously carried a source-time conversion no longer needs one — a small example of the scope change paying for itself.

## Session and route

The session is configured for **playback only** — never for recording, on any code path. A record-capable session would prompt for microphone access and, on some routes, force a lower-quality output path. Neither is acceptable.

### Output routes (FR-014, FR-017 … FR-019)

```swift
struct OutputRoute {
    let kind: RouteKind          // bluetoothA2DP, builtInSpeaker,
                                 // wiredLineOut, usbAudio, airPlay, other
    let isExternal: Bool         // false ⇒ the device's own speaker
    let outputLatencyMs: Double  // what the words must be shifted by (FR-019)
    let degradesQuality: Bool    // true for any re-encoding wireless route (FR-014)
}
```

**`degradesQuality` is not decoration.** Bluetooth re-encodes the decoded audio before transmitting it. Since the source is already lossy, that is a lossy-to-lossy transcode and it is the narrowest point in the entire chain — narrower than any difference between upstream renditions. The flag exists so the app can be honest about an audio quality it cannot deliver, rather than advertising a rendition bitrate that the link then discards. This is the mechanism behind the *Audio Quality Reality* section of [spec.md](../spec.md).

**`outputLatencyMs` drives the display.** The player reports what it has dispatched; the speaker emits it a sixth of a second or more later. The lyrics layer subtracts this value. Because Bluetooth is the only supported route, an implementation that omits the subtraction is wrong for every song, not occasionally — which is why it gets its own validation scenario rather than a line in a checklist.

The system's reported latency is frequently inaccurate for third-party wireless speakers, which is why FR-020 provides a manual trim layered on top.

**Losing the route pauses playback** (FR-018). If the Bluetooth link drops, audio must not fall through to the device's own speaker at party volume. The pipeline pauses and emits `externalOutputLost`. On reconnection it offers to resume from the paused position rather than restarting.

**A degrading link is not a playback fault.** Stutter from interference or distance must not be mistaken for a buffering problem and must never trigger stream re-resolution — re-resolving in response to a radio problem makes it worse and wastes quota.

### Interruptions (FR-016)

On interruption the pipeline pauses and retains position. On interruption end it emits an event and waits — it does not auto-resume. A call ending should not blast music at the room mid-conversation.

### Background (FR-015)

Audio continues when backgrounded or the screen locks. Track information is published to the now-playing surface and transport controls are wired to play, pause, seek, and next. This is the normal case: the iPad spends most of a party on a table, locked.

## Events

```swift
enum AudioPipelineEvent {
    case stateChanged(PlaybackState)
    case positionUpdated(PlaybackPosition)
    case reachedEnd
    case routeChanged(OutputRoute)
    case externalOutputLost(previous: RouteKind)   // FR-018 pause trigger
    case externalOutputRestored(OutputRoute)       // offer to resume
    case interrupted
    case interruptionEnded(shouldResume: Bool)
    case stalled                                    // buffering or link trouble
    case error(AudioError)
}
```

`stalled` is reported but deliberately *not* acted on by re-resolution — see the degrading-link rule above.

## Errors

```swift
enum AudioError: Error {
    case sessionConfigurationFailed(detail: String)
    case unsupportedFormat(codec: String, container: String)
    case sourceUnreadable(detail: String)
    case seekOutOfBounds(requested: Double, duration: Double)
    case noExternalOutput
}
```

`unsupportedFormat` triggers the Selection Rule's fallback to the next-best playable rendition — the pipeline reports it rather than failing the song. This is the case that matters most in practice: the highest-bitrate rendition a source offers is frequently in a container the platform will not decode.

## Behavioural requirements

1. **The player's clock is the only clock.** Position, lyric timing, and progress all read `position`. Nothing accumulates its own timer — that is how SC-008 drift appears.
2. **Route delay is published, not assumed.** `outputLatencyMs` is read from the live route on every change. No hardcoded Bluetooth constant.
3. **Nothing processes the samples except what the singer turned on.** Apart from volume and the tone control (FR-043), the output is the decoded source. No resampling, no normalisation, no automatic "enhancement" — nothing the singer did not ask for. With the tone control bypassed or flat, SC-007 verifies bit-identity by capture.
4. **Seek is atomic for observers.** Once `seek(to:)` returns, `position` reflects the new value. A dependent view must never observe the old position afterwards (FR-023).
5. **Never records.** Playback-only session on every code path, with no conditional that could configure otherwise.
6. **Link trouble is not stream trouble.** A stall never triggers re-resolution.
7. **Sustained operation.** Two hours continuous with no crash, no dropout, bounded memory (SC-009).

## Test contract

Automated (Principle IV — logic that rots silently):

- **Session category**: playback-only on every path through `prepare`. This test is what keeps FR-010 true as the code changes.
- **Volume clamping**: out-of-range values clamped before reaching the player. At party volume this is a hearing-safety matter, covered regardless of how obvious it looks.
- **Route classification**: a table of route descriptors maps to the correct `kind`, `isExternal`, `degradesQuality`, and delay.
- **External-output-lost handling**: losing the route produces a pause and the event, never continued playback; restoration offers resumption at the paused position, not a restart.
- **Stall handling**: a stall produces `stalled` and provably does **not** trigger re-resolution.
- **Seek bounds**: out-of-range seeks yield `seekOutOfBounds` rather than clamping silently.

On-device only (Principle III — simulator results do not count):

- Captured output is the decoded source apart from level (SC-007).
- Measured display-versus-audio alignment over the Bluetooth speaker (SC-008). The scenario that justifies FR-019 existing.
- Measured and reported route delay versus actual, to size the FR-020 manual trim.
- Two-hour continuous session through the real PA speaker: no crash, no dropout, bounded memory (SC-009).
- Background and lock-screen continuity and transport controls (SC-010).
- Link drop and restore mid-song behave per FR-018.
- No microphone prompt ever appears and the app never registers microphone access (SC-003).
