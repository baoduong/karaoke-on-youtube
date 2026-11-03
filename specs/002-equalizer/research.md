# Phase 0 Research: Equalizer

**Feature**: 002-equalizer | **Date**: 2026-11-03

The feature rests on one question that had to be answered before anything
else: can audio be processed at all on the path this app actually plays?
Everything below follows from that answer.

---

## R1. Can an equalizer be applied to HLS playback on iOS?

**Decision**: Yes, but only on iOS 27 or later, using
`AVAudioMixInputParametersTrackMixID`. On iOS 17–26 it is impossible.

**Rationale**

Apple's documentation for `AVPlayerItem.audioMix` states it verbatim:

> An audio mix can only be used with file-based media and is not supported
> for use with media served using HTTP Live Streaming.

The mechanism behind the restriction is in `AVPlayerItem.h`: audio mix input
parameters are matched to the asset by `trackID`, and an HLS `AVURLAsset` has
no static track table — `loadTracks(withMediaType: .audio)` returns an empty
array, because HLS demuxes segments and switches variants inside
`mediaserverd`. With no track to match, the mix is silently ignored and the
`MTAudioProcessingTap` callbacks never fire. Silently is the operative word:
the API accepts the assignment and does nothing.

iOS 27 added `AVAudioMixInputParametersTrackMixID` (a `trackID` of `0`)
meaning "apply to the mix of all audio tracks rather than one track". Its own
header names streaming as the motivating case. iOS 27 also added
`AVPlayerItemSampleBufferOutput`, documented as "currently supported for HLS
`AVPlayerItems` only, and only for delivering decoded PCM audio". That Apple
had to add both in the same release is the strongest available confirmation
that no mechanism existed before.

**Why this is usable here despite the iOS 17 deployment target**

Measured on this project's hardware:

| | Version |
|---|---|
| Physical device (`00008140-001045C11E63001C`, iPhone 16 Pro) | **iOS 27.2** |
| Installed SDK | iOS 27.2 |
| Installed simulator runtimes | iOS 26.2, 26.5 — **no iOS 27** |

The one device that will ever run this app is already on iOS 27.2. Under
Principle VII, building a second playback architecture to serve iOS versions
no device in this project runs would be an abstraction that does not pay for
itself.

The deployment target therefore stays at 17.0 and the equalizer is gated
behind `if #available(iOS 27.0, *)`. Keeping the target low is not about
supporting old phones — it is so the 277-test suite keeps running on the
iOS 26.2 simulator, which is the only runtime installed.

A consequence to accept openly: **the equalizer cannot be exercised in the
simulator at all.** Principle III already says simulator results do not count
for anything involving audio, so this costs no verification that was ever
going to be trusted. It does mean every EQ change is verified on the device
or not at all.

**Alternatives considered**

- *`AVMutableComposition` over progressive URLs.* Fetch the googlevideo video
  and audio streams as progressive byte-range URLs, compose them, and get real
  `AVCompositionTrack`s with persistent IDs — on which `audioMix` works all
  the way back to iOS 17. Rejected: it replaces adaptive HLS with a fixed
  rendition, adds a `moov`/`sidx` fetch to startup, and the companion service
  would have to expose a second URL shape. All to support an OS version no
  device here runs.
- *Dual player: video muted on HLS, audio from the progressive `.m4a`.* Works
  on iOS 17, and would make all three source paths non-HLS so one EQ
  implementation covers them. Rejected: it introduces a second clock and an
  A/V synchronisation problem that currently does not exist. The video carries
  the words; drift between picture and sound is precisely the defect the app
  spends effort avoiding (FR-019, SC-008).
- *VLCKit or KSPlayer (FFmpeg).* Both offer multi-band EQ on HLS today, on any
  iOS version. Rejected under Principle VII: a large binary dependency
  replacing the entire playback layer, to avoid an `@available` check.
- *A system-level or `AVAudioSession` equalizer.* Does not exist.
  `AVAudioSession` exposes routing, category, mode, sample rate and buffer
  duration, and no frequency response control whatsoever. The EQ in
  Settings → Music applies only to Apple's own Music app. The macOS
  `CATapDescription` process-tap API has no iOS counterpart.

---

## R2. What performs the filtering inside the tap?

**Decision**: `AVAudioEngine` in `.realtime` manual-rendering mode, hosting a
single `AVAudioUnitEQ`, driven from the `MTAudioProcessingTap` process
callback via `engine.manualRenderingBlock`.

**Rationale**

`AVAudioUnitEQ` is Apple's own filter implementation, already tuned and
already real-time safe. Manual rendering mode exists for exactly this —
driving an engine from someone else's callback — and `.realtime` is the
documented mode for a render thread. This is a known production pattern, not
an invention.

Principle VII argues against hand-writing filter mathematics when the platform
ships it. Principle I argues for using code already written to be
render-safe rather than new code that must be proven so.

**Alternatives considered**

- *Hand-written biquad coefficients in C with atomics.* Full control, no
  engine inside a tap, and a smaller thing to reason about on the render
  thread. Rejected as the first choice: it is filter math this project would
  then own and have to get right, for a result `AVAudioUnitEQ` already
  provides. Kept as the fallback if manual rendering proves unstable inside a
  tap on device.
- *`AVAudioUnitEQ` on a full `AVAudioEngine` graph instead of `AVPlayer`.*
  Requires feeding PCM into the engine, which means demuxing and decoding the
  stream in-app. `AVAudioEngine` has no URL or HLS input of any kind.

---

## R3. How do parameter changes reach the render thread?

**Decision**: They do not. Gains are set on `AVAudioUnitEQ` from the main
thread and never cross the render callback as data at all.

**Rationale**

This was planned as a hand-built lock-free snapshot, and that turned out to be
work the platform had already done. `AVAudioUnitEQ`'s band gains are AudioUnit
parameters, which are built to be set from any thread, and the unit ramps them
internally — which also satisfies the no-click requirement without a ramp of
our own.

So the render callback reads no parameters. It calls
`engine.manualRenderingBlock` and copies buffers, and that is the whole of it.
This is most of the reason `AVAudioUnitEQ` beat hand-written biquads: not the
filter maths, but the parameter path that comes with it.

Principle I still governs what the callback does: no allocation, no locking,
no logging, no Swift runtime dynamism. Every buffer is allocated in `prepare`.

**A memory-safety trap found by running the suite, not by reading**

The tap's `clientInfo` initially held an *unretained* pointer to the owning
object. The tap outlives the player item that carries it, so during teardown
the callbacks dereferenced freed memory. On iOS 26.2 this crashed the test
host partway through the suite; on iOS 27.2 the same build passed, because a
use-after-free is nondeterministic. Fixed by retaining in
`MTAudioProcessingTapCreate` and releasing in the `finalize` callback, which
is what that callback is for.

Worth recording because the fix looks like a leak to a reader, and reverting
it reintroduces a crash that only shows up sometimes.

**Alternatives considered**

- *Reading an `@Observable` property from the callback.* Rejected: Swift
  runtime access on the render thread, directly against Principle I.
- *A lock around the parameters.* Rejected: priority inversion on the render
  thread is the textbook cause of dropouts, and a dropout here is a defect of
  crash severity.
- *A hand-built atomic snapshot.* Not wrong, just unnecessary once the
  AudioUnit parameter path was understood.

---

## R4. How many bands, and what shape?

**Decision**: Three bands — low shelf, mid peaking, high shelf — with gain in
the range ±12 dB, flat at 0 dB, plus a master bypass.

**Rationale**

The stated need is "turn the treble up a bit, or the bass down a bit" on songs
that sound wrong through the PA. Three bands serve that directly. A ten-band
graphic EQ would serve it no better while giving the singer nine more things
to get wrong mid-party, and Principle VII asks every addition to pay for
itself.

±12 dB is the conventional range for a tone control and is enough to rescue a
dull or boomy upload without inviting the kind of boost that clips.

**Open question, deliberately not decided here**

Whether gains are **global** or **remembered per song**. The request mentions
specific songs sounding wrong, which argues for per-song memory; but global is
a smaller first step and per-song can be added without redesigning anything
(the settings entity already has a song-keyed store next to it). Recorded in
plan.md as a decision for the user, not an assumption.

---

## R5. Does clipping need handling?

**Decision**: Yes. A boost of +12 dB on material already mastered near full
scale will clip. A limiter is **not** added; instead the summed gain is
applied with headroom by attenuating the overall level in proportion to the
largest positive band gain.

**Rationale**

A limiter is dynamics processing — it changes the material in a way the
singer did not ask for, and it is a second processor to reason about on the
render thread. Trading a little level for no clipping is the honest option,
and the PA has its own volume control for the result.

**Alternatives considered**

- *`AVAudioUnitEffect` peak limiter after the EQ.* Rejected for the reason
  above, and because Pocket Casts' use of one is for a different purpose
  (speech levelling).
- *Ignoring clipping.* Rejected: distortion at volume is exactly the complaint
  the feature exists to fix.
