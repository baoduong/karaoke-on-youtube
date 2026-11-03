# Implementation Plan: Equalizer

**Branch**: `002-equalizer` | **Date**: 2026-11-03 | **Spec**: not yet written — see Gate Status

**Input**: User request, 2026-11-03. No `spec.md` exists for this feature yet.

---

## Summary

Give the singer a three-band tone control — low shelf, mid, high shelf, ±12 dB
— that takes effect live on the song currently playing, so a dull or boomy
karaoke upload can be corrected from the phone instead of by walking to the PA
speaker and adjusting it there for every song.

Technically this is possible on this project's hardware and nowhere near
universally: processing audio on an HLS stream requires
`AVAudioMixInputParametersTrackMixID`, added in **iOS 27**. The one physical
device here runs iOS 27.2. See `research.md` R1 for the evidence and for the
three architectures rejected along the way.

---

## Gate Status: **CLEARED** — amended in `77d4e3f`, implemented after

The blocker below was real and has been resolved in the order the constitution
requires: the specification was amended in its own commit, carrying its own
reasoning, before any code was written.

Four shipped artifacts forbade the feature by name (FR-009 was found after the
first three). The amendment narrowed each to forbid *automatic* processing
while permitting a control the singer turns on, and added FR-043 and SC-015.

What follows is the original analysis, kept because the reasoning is the point.

| Artifact | Text that forbids it |
|---|---|
| `spec.md` **SC-007** | "Audio output is **bit-identical to the decoded source apart from level, verified by capture**." |
| `spec.md` **FR-012** | "System MUST select and play the best rendition available rather than **attempting to improve a lesser one by processing**." |
| `contracts/audio-pipeline.md` invariant 3 | "Nothing processes the samples. Apart from volume, the output is the decoded source. No resampling, no normalisation, **no EQ**, no 'enhancement'." |

These are not incidental wording. SC-007 is a success criterion with a stated
verification method — a capture proving bit-identity — and an equalizer makes
that capture fail by design. FR-012 encodes a deliberate position: choose a
better source rather than repair a worse one.

What the constitution says about this situation:

> Where it conflicts with a convenient implementation, the constitution wins
> or the constitution is amended first, in a separate change, with the
> reasoning recorded.

**The constitution itself does not forbid an equalizer.** Principle I governs
the real-time audio path rather than prohibiting it, and it reads as though
written in anticipation of exactly this kind of work. The repository's
SwiftLint rules do not forbid it either: `no_pitch_tempo` names
`AVAudioUnitTimePitch` and `AVAudioUnitVarispeed`, and `AVAudioUnitEQ` is
absent from every custom rule. The conflict is with the feature specification,
not with the project's principles.

### Required amendment, before any code

1. **FR-012** — narrow its scope to rendition selection, which is what it is
   really about. Proposed: *"System MUST select and play the best rendition
   available rather than compensating for a lesser one. Tone shaping the
   singer explicitly asks for is not a substitute for rendition quality and
   does not relax this requirement."*
2. **SC-007** — split the claim. The no-click, 200 ms responsiveness half
   stays as is. The bit-identity half becomes conditional: *"With the
   equalizer bypassed, audio output is bit-identical to the decoded source
   apart from level, verified by capture."* Bypass then becomes a testable
   state rather than a permanent property.
3. **`contracts/audio-pipeline.md` invariant 3** — rewrite as: *"Nothing
   processes the samples except what the singer asked for. With EQ bypassed
   the output is the decoded source apart from level. No resampling, no
   normalisation, no automatic 'enhancement' — nothing the singer did not
   turn on."*
4. A new **FR** for the equalizer itself, and a new **SC** stating its
   measurable criterion (see Success Criteria below).

Amending the spec is a `/speckit.specify` or manual-edit task. It is
deliberately **not** done by this plan.

---

## Technical Context

**Language/Version**: Swift 6.0, strict concurrency complete

**Primary Dependencies**: AVFoundation (`AVPlayer`, `AVAudioMix`,
`MTAudioProcessingTap`), AVFAudio (`AVAudioEngine` manual rendering,
`AVAudioUnitEQ`), SwiftData, SwiftUI

**Storage**: SwiftData — `PerformanceSettings`, which currently holds a single
field after the lyrics layer was removed and is the natural home

**Testing**: Swift Testing. Pure logic only — gain clamping, headroom
calculation, preset mapping, settings persistence. The filter itself and the
tap wiring are verified by ear and by capture on the device, per Principle IV,
which explicitly exempts audio graph wiring from automated testing.

**Target Platform**: iOS 17.0 deployment target retained; the equalizer itself
is `@available(iOS 27.0, *)`. Physical device runs iOS 27.2.

**Project Type**: Sideloaded iOS/iPadOS application, single developer, single
household

**Performance Goals**: A gain change is audible within 200 ms with no click,
matching the existing volume criterion. No added dropouts in a two-hour
session (SC-009 must continue to hold).

**Constraints**: Principle I in full — the render callback allocates nothing,
locks nothing, logs nothing, and performs no Swift runtime dynamism. Parameter
changes cross to the render thread through a lock-free snapshot. No pitch or
tempo change of any kind (FR-011 is untouched by this feature and stays).

**Scale/Scope**: Three bands, one bypass, one settings screen section, one
control surface on the player. No presets beyond "Flat" in the first cut.

---

## Constitution Check

*GATE: evaluated before Phase 0, re-evaluated after Phase 1 design.*

| Principle | Verdict | Note |
|---|---|---|
| **I. The Audio Path Is Sacred** | **Applies in full** | This is the first feature to add a render callback. Lock-free parameter passing and ramped gain changes are designed in, not retrofitted. Every change here carries the real-time-safety note Gate 4 requires. |
| **II. The Upstream Will Break** | Not engaged | No new upstream interaction. The EQ sits after decode and knows nothing about sources. |
| **III. Verify the Claim, Not the Code Path** | **Applies, and bites** | EQ cannot run on the simulator at all — no iOS 27 runtime is installed. Every claim about it must be measured on the device. This matches what Principle III already demanded for audio. |
| **IV. Test What Can Silently Rot** | Applies narrowly | Gain clamping, headroom maths and settings persistence get tests. Filter wiring does not — the principle names audio graph wiring as exempt. |
| **V. Nothing Leaves the Device** | Satisfied | No new outbound destination. Settings stay in SwiftData. |
| **VI. Honest Failure Over Silent Degradation** | **Applies** | On a device below iOS 27 the control must say why it is unavailable, not silently do nothing — which is exactly what `audioMix` itself does on HLS, and the trap this feature is built around. |
| **VII. One Developer's Scale** | **Drives the design** | Three bands not ten. `AVAudioUnitEQ` rather than hand-written biquads. An `@available` check rather than a second playback architecture for iOS versions no device here runs. |

**Specification gates**: **FAIL** — SC-007, FR-012 and `audio-pipeline.md`
invariant 3, as set out in Gate Status above. Amendment required first.

**Post-Phase-1 re-evaluation**: no new violations introduced by the design
below. The specification conflict is unchanged and remains the sole blocker.

---

## Project Structure

### Documentation (this feature)

```text
specs/002-equalizer/
├── plan.md              # This file
├── research.md          # Phase 0 — the HLS feasibility question and what was rejected
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1 — device validation scenarios
├── contracts/
│   └── equalizer.md     # Phase 1 — pipeline contract and real-time rules
└── tasks.md             # Phase 2 — NOT created by /speckit.plan
```

### Source Code

```text
Karaoke/Karaoke/
├── Audio/
│   ├── AudioPipeline.swift        # protocol gains EQ parameter surface
│   ├── PlayerPipeline.swift       # attaches AVAudioMix with trackMixID
│   ├── EqualizerSettings.swift    # NEW — value type crossing to the render thread
│   └── EqualizerTap.swift         # NEW — MTAudioProcessingTap + manual-rendering engine
├── Store/Models/
│   └── PerformanceSettings.swift  # gains persisted here
└── Features/
    ├── Player/PlayerView.swift    # entry point to the control
    └── Settings/EqualizerView.swift  # NEW — the three sliders and bypass

Karaoke/KaraokeTests/
└── Audio/
    └── EqualizerTests.swift       # NEW — clamping, headroom, persistence
```

**Structure Decision**: The existing layout is kept. `Audio/` already holds the
pipeline and session controller; the tap and its parameter type belong beside
them. No new module: Principle VII requires a second implementation or a
real-time-safety reason for a module boundary, and neither applies.

---

## Success Criteria (proposed, for the spec amendment)

- **SC-EQ-1**: A band gain change is audible within 200 ms, with no click, gap
  or dropout — measured on the device through the Bluetooth PA.
- **SC-EQ-2**: With the equalizer bypassed, output is bit-identical to the
  decoded source apart from level, verified by capture. This is the surviving
  half of SC-007.
- **SC-EQ-3**: A two-hour session with the equalizer active completes with no
  dropout and no unbounded memory growth (SC-009 continues to hold).
- **SC-EQ-4**: On a device below iOS 27 the control states why it is
  unavailable rather than appearing functional (Principle VI).

---

## Outcome

Implemented and verified on simulator. Device verification is still owed and
is listed in `quickstart.md`.

| Measured | Result |
|---|---|
| Suite, iOS 26.2 and iOS 27.2 | 298 tests in 53 suites, exit 0, no crash-restarts |
| HLS attachment, iOS 27.2 | `isEqualizerAvailable == true` |
| HLS attachment, iOS 26.2 | `isEqualizerAvailable == false` — refusal reported, not silent |
| File attachment, both | `true` |

Two things were learned by running rather than reading, and both are recorded
where they will be found again: the tap for a track mix must be created with
`MTAudioProcessingTapCreateWithPreferredFormat` or its format is undefined,
and `clientInfo` must retain its owner or teardown is a use-after-free that
crashes on one OS version and passes on another.

Decisions taken without asking, since the user delegated them:

- **Global, not per-song.** Smaller first cut; `data-model.md` records how
  per-song would be added without redesign.
- **On the player, not in Settings.** "Without walking to the PA every time"
  is the point, and the moment a song sounds wrong is while it is playing.

## Open Decisions for the User

1. **Global or per-song?** The request named specific songs that sound wrong,
   which argues for remembering gains per song. Global is the smaller first
   cut and per-song can be layered on later without redesign. Recommendation:
   ship global first, measure whether it is actually annoying to re-adjust.
2. **Where does the control live?** A section in Settings is cheapest. A
   control reachable from the player is more useful mid-song, which is when
   the problem is noticed. Recommendation: a compact control on the player,
   since "without walking to the PA every time" is the point of the feature.

---

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A real-time render callback, the first in this codebase | No iOS API applies an equalizer to `AVPlayer` output without one; there is no system EQ for third-party apps | `AVAudioSession` has no frequency-response control at all, and the Settings → Music EQ reaches only Apple's own app (`research.md` R1) |
| `@available(iOS 27.0, *)` gate, leaving the feature dead on older systems | `audioMix` is ignored on HLS before iOS 27, silently | Supporting iOS 17–26 requires either `AVMutableComposition` over progressive URLs, a second synchronised player, or FFmpeg — each a parallel playback architecture, for devices this project does not have |
