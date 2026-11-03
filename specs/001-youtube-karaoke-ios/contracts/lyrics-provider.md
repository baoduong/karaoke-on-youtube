# Contract: LyricsProvider

**Feature**: `001-youtube-karaoke-ios` | **Phase**: 1 (Design)

Optional synchronized text layer. Most karaoke sources carry the words in the video image, so this is an enhancement, not a dependency — the app must be fully usable with no provider configured.

**Satisfies**: FR-022 (SHOULD), FR-023, FR-024

## Scope and non-scope

**In scope**: fetching a time-coded text track for a song, parsing it, validating its timing, and exposing a lookup that answers *which segment is current at this audio position*.

**Out of scope**: the app does not author, host, redistribute, or cache-for-sharing any text track. Fetched tracks are stored locally only for songs the singer has saved offline, and never leave the device (Constitution Principle V). No provider is enabled by default; the singer opts in, and the chosen provider's terms are the singer's to accept.

## Protocol

```swift
protocol LyricsProvider: Sendable {
    var identifier: LyricsProviderID { get }

    /// Whether the singer has enabled this provider. Nothing is fetched otherwise.
    var isEnabled: Bool { get }

    /// Returns nil when no track is available — a normal, expected outcome,
    /// not an error. Most songs will have none.
    func lyrics(for query: LyricsQuery) async throws(LyricsError) -> LyricsTrack?
}

struct LyricsQuery {
    let title: String
    let artist: String?
    let durationSeconds: Int     // used to reject a mismatched track
}
```

`durationSeconds` is required, not optional. Matching on title alone returns the wrong song often enough that a duration check is the difference between a useful feature and a confusing one.

## Errors

```swift
enum LyricsError: Error {
    case offline
    case rateLimited(retryAfter: TimeInterval?)
    case providerUnavailable(detail: String)
    case malformedResponse(detail: String)
    case timeout
}
```

No case means "not found" — absence is `nil`, not an error. Every error here is non-fatal: the performance proceeds with the video image. A lyrics failure must never interrupt or delay playback.

## Parsing and validation

Input is a time-coded text format, either line-level or with per-word timings. Validation is where this contract earns its place, because bad timing data produces jumping, unreadable highlights that are worse than no highlight at all.

A track is **rejected** when:

1. Line start times are not strictly increasing.
2. A line's end time is not greater than its start, or exceeds the next line's start.
3. Word start times within a line are not strictly increasing, or fall outside the enclosing line's bounds.
4. The last start time exceeds the song duration by more than a small tolerance — almost certainly the wrong song.
5. The track is empty or contains no timed entries.

Rejection yields `nil`, logged locally with the reason. Empty text on a timed line is *not* a rejection: an empty line is a legitimate instrumental-gap marker.

Parsed output is the `LyricsTrack` / `LyricsLine` / `LyricsWord` shape defined in [data-model.md](../data-model.md).

## Timing contract

The part that determines whether SC-008 passes.

```swift
protocol LyricsTimeline {
    /// Pure function. Same inputs, same output, no clock of its own.
    func position(atSourceTime seconds: Double) -> LyricsPosition
}

struct LyricsPosition {
    let lineIndex: Int?          // nil before the first line or after the last
    let wordIndex: Int?          // nil when the track has no word timing
    let progressWithinWord: Double   // 0...1, for a smooth wipe
}
```

**Rules**

1. **The player's clock is the only source of truth.** Lookup input is `PlaybackPosition.seconds` from the [AudioPipeline](./audio-pipeline.md). No wall-clock timer, no accumulated frame counter, no independent playback estimate. A display refresh callback decides *when to ask*; it never decides *what time it is*.
2. **Playback rate is always 1.0** (FR-011), so no rate conversion enters the lookup. The position is the source time.
3. **Seek corrects in the same update.** After a seek, the next lookup returns the correct position immediately. The highlight does not animate toward the right place over subsequent frames (FR-023).
4. **Output delay is subtracted** (FR-019). Effective time = position − the active route's `outputLatencyMs` + the track's global offset + the singer's manual trim.

   This is the easiest rule here to omit and by far the most consequential. The player reports what the device has *dispatched*; the Bluetooth speaker emits it a sixth of a second or more later. Skip the subtraction and the words run visibly ahead of the sound. Because Bluetooth is the only supported route, an implementation that omits this is wrong for every song rather than occasionally — there is no configuration in which the mistake hides. FR-020's manual trim sits on top, for speakers whose reported delay is inaccurate.
5. **Lookup is pure and cheap.** It is called at display refresh rate. It performs no allocation and no I/O, and runs in better than linear time over lines — a binary search over start times, with the previous index as a hint.
6. **Accuracy budget.** The displayed position stays within 150 ms of the audio **as heard from the Bluetooth PA speaker** over a full song including three seeks (SC-008).

## Rendering requirements (FR-024)

- Legible at room viewing distance on iPad; the singer can scale the text (`lyricsFontScale`, 0.5 … 3.0).
- The current line is visually distinguished from its neighbours. With word timing, the current word is distinguished within the line.
- Upcoming lines are visible so the singer can read ahead — a karaoke display showing only the current line is useless for singing.
- Rendering never blocks on a fetch. A track that arrives mid-song fades in; one that never arrives changes nothing.

## Behavioural requirements

1. **Disabled by default.** No network request is made for text until the singer enables a provider.
2. **Never blocks playback.** Fetch is concurrent with resolution and playback. A slow or failing provider has no effect on time-to-first-audio (SC-006).
3. **Cached per song, locally.** A fetched track is reused for the session. It is persisted only for songs saved offline, and only on the device.
4. **No provider configured is a normal state**, not a degraded one. The video image carries the words for most sources.

## Test contract

Automated (Principle IV — timing logic rots silently and fails invisibly):

- **Parser**: well-formed line-level and word-level inputs produce the expected structure, using synthetic placeholder text in fixtures.
- **Validation**: each of the five rejection rules is exercised and returns `nil` with the right reason. The duration-mismatch rule is the one that prevents the wrong song's words appearing, so it is covered explicitly.
- **Lookup**: given a synthetic track, lookup at boundary times returns the correct line and word — before the first line, exactly on a boundary, mid-word, in a gap, and after the last line.
- **Seek correction**: a jump to an arbitrary position returns the correct index on the first lookup, with no intermediate wrong value.
- **Offset**: a non-zero global offset shifts the resolved position by exactly that amount.
- **Route-delay compensation**: with a non-zero route delay, lookup returns the line and word that will be *heard* at that moment, not the one being dispatched. Asserted against a table of delay values, including zero.

On-device (Principle III):

- Drift measured over a full song with three seeks, against the SC-008 budget, over the Bluetooth speaker. This is the only supported route, so it is the only one that must pass — and it is the one that fails when rule 4 is omitted. A wired measurement is still worth taking once, as a calibration reference for how much of the observed gap is the link rather than the code.
- Legibility at room distance on iPad at the default and minimum font scales.

Fixtures use synthetic placeholder text only. No real song text is committed to this repository.
