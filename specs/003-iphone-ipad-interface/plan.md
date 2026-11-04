# Implementation Plan: Professional iPhone and iPad Interface

**Branch**: `003-iphone-ipad-interface` | **Date**: 2026-11-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-iphone-ipad-interface/spec.md`

## Summary

Make the iPhone interface professional, on the understanding that **there is no television**:
the phone is the screen the singer reads the words from, because the karaoke video carries its
lyrics in the picture. Three things follow, and they are this plan's whole content.

Keep the words readable — the video becomes the largest thing on the player, it fills the
screen when the phone is turned on its side, and nothing ever covers or dims it, including the
tone control, which stops being a sheet and becomes part of the layout. Put every mid-song
control where a thumb can reach it while the other hand holds a microphone. Give the app one
visual language: a typographic scale that actually responds to the system text size, which the
current seven hard-coded sizes do not, plus the removal of doubled navigation bars, a
duplicated favourites list, one screen that ignores the design system, and a colour collision
between "selected" and "something is wrong".

**The iPad is deliberately out of scope for this round**, at the owner's instruction. Spec
Stories 4 and 5 remain in the specification, unimplemented.

## Technical Context

**Language/Version**: Swift 6.0, with `SWIFT_STRICT_CONCURRENCY: complete` project-wide

**Primary Dependencies**: SwiftUI, AVKit (`VideoPlayer`), SwiftData. One third-party package,
`YouTubeKit` 0.4.10 via SPM (`Karaoke/project.yml:41`), which this feature does not touch.

**Storage**: SwiftData, on device only. This feature adds no stored data; typography tokens are
compile-time constants and the one new user-facing control acts on the existing queue.

**Testing**: swift-testing (`import Testing`) across all 29 existing test files. Zero XCTest.
Physical-device verification for anything visual, per Principle III.

**Target Platform**: iOS 17.0, iPhone. Device family is already universal (`"1,2"`) and stays
that way; this round simply does not design for the wider class.

**Project Type**: Mobile application, single target, generated from `Karaoke/project.yml` with
XcodeGen. The `.xcodeproj` is a build artifact and is gitignored.

**Performance Goals**: No dropped frames and no audio interruption across an orientation
change. Playback position preserved exactly. The existing release bar — thirty continuous
minutes with no crash, dropout, or advertisement — continues to apply.

**Constraints**: Nothing may overlap or dim the video while a song plays. Space taken by larger
system text may not be taken from the video. Mid-song controls must sit within one-handed thumb
reach. Text contrast at least 4.5:1, including on filled accent controls, where today's white
on amber measures about 1.9:1.

**Scale/Scope**: 13 screens, 24 SwiftUI view structs across 14 files. Seven hard-coded text
sizes to replace. One 620-line root view that hosts the tab shell, the player, and a tab's
content at once.

**Orientation note that is easy to get wrong**: "skip the iPad" does not mean "skip regular
width". A large iPhone in landscape reports a regular horizontal size class. The landscape work
in this plan therefore applies to phones and is driven by the **vertical** size class. What is
deferred is the regular-width *layout redesign* of Stories 4 and 5, not every width-aware
behaviour.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Verdict | Basis |
|---|---|---|
| I — The Audio Path Is Sacred | **Pass** | No render callback is touched. Relocating the tone control changes where its UI lives, not how its values reach the audio path. FR-006 touches player lifecycle, not the render thread; R2 exists precisely so the player is never torn down. |
| II — The Upstream Will Break | **Pass, not engaged** | No new upstream interaction. The `SourceProvider` boundary is untouched. |
| III — Verify the Claim, Not the Code Path | **Pass, binding** | Nine of fourteen success criteria require a physical device. No simulator result counts for legibility, reach, or rotation behaviour. Recorded in `quickstart.md`. |
| IV — Test What Can Silently Rot | **Pass, with one addition** | The constitution exempts SwiftUI layout from automated tests, and most of this feature is layout. One thing here *can* rot silently and gets a test: the rule that no call site specifies a raw text size (SC-007), which is a mechanical check, not a visual one. |
| V — Nothing Leaves the Device | **Pass** | No new outbound destination. No change to network behaviour. |
| VI — Honest Failure Over Silent Degradation | **Strengthened** | FR-022 forbids colour-only state, and FR-021 separates "selected" from "content problem", which today share the amber hue. |
| VII — One Developer's Scale | **Pass** | One new abstraction, the typography token. It pays for itself by replacing seven scattered literals and is required explicitly by Principle VIII. `AnyLayout` is used for both orientation and accessibility reflow so the codebase learns one pattern, not two. |
| VIII — iPhone First, iPad On Purpose | **Deviation, recorded below** | The iPhone half is this plan's subject. The iPad half is deferred at the owner's instruction, leaving the iPad in the state Principle VIII forbids. |
| Quality Gate 7 — reachability | **Pass, binding** | This feature adds a next-song control and moves the tone control. Both must be *operated*, not merely rendered. Recorded in `quickstart.md`. |

### Deviation: Principle VIII, iPad half deferred

Principle VIII says the iPad must not be served by a stretched iPhone layout. After this plan,
it still is.

This is a sequencing decision, not a new breach. The stretched layout exists today; this plan
neither introduces nor worsens it. Principle VIII itself names the iPhone as the reference
platform, and the owner asked for iPhone first in those words. Specification Stories 4 and 5
remain written, prioritised, and unimplemented, so the debt is recorded rather than forgotten.

Shipping a *wrong* iPad layout in a hurry would breach the principle. Leaving it untouched
while the reference platform is put right does not.

## Project Structure

### Documentation (this feature)

```text
specs/003-iphone-ipad-interface/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── typography.md
│   ├── player-layout.md
│   └── screen-structure.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
Karaoke/
├── project.yml                               # XcodeGen source of truth
└── Karaoke/
    ├── KaraokeApp.swift                      # @main
    ├── RootView.swift                        # 620 lines — tab shell, player host,
    │                                         #   starting overlay, Library tab list
    ├── Common/
    │   └── KaraokeTheme.swift                # Palette / Space / Radius / Hit
    │                                         #   -> gains Typography (this feature)
    └── Features/
        ├── Search/SearchView.swift
        ├── Player/
        │   ├── PlayerView.swift              # transport
        │   ├── PlayerVideoStage.swift        # 16:9 stage, route badge
        │   ├── SourceVideoView.swift         # AVKit.VideoPlayer wrapper
        │   ├── SuggestionsView.swift
        │   ├── EqualizerView.swift           # sheet today -> inline panel
        │   ├── QualityDetailView.swift
        │   └── PlaybackErrorView.swift
        ├── Queue/QueueView.swift
        ├── Library/{LibraryView,SavedSongsView}.swift
        └── Settings/{SettingsView,SigningValidityView}.swift

Karaoke/KaraokeTests/                         # 29 files, swift-testing
Tools/shoot-screens.sh                        # simulator capture harness
```

**Structure Decision**: The existing feature-folder layout is kept unchanged. Typography joins
the other design tokens in `Common/KaraokeTheme.swift`, beside `Palette`, `Space`, `Radius` and
`Hit`, because that file is already the one place the project looks for shared visual values.

The player is where the structural work lands. `RootView.swift` currently hosts the tab shell,
the player screen, the starting overlay and the Library tab's root list in one 620-line file,
and the player half of it has to be reshaped for the orientation work in R2 to be possible at
all — a single `VideoPlayer` at a fixed structural position cannot be arranged while the player
is assembled inline inside a tab's conditional. Extracting the player host is therefore a
prerequisite of Story 1, not a tidy-up. It is invisible to the user and carries no user story
of its own.

## Requirement Traceability

Every functional requirement is either carried by an artifact below or explicitly deferred.
There is no third category.

### In scope this round — 21 requirements

| Requirement | Carried by |
|---|---|
| FR-001 video is the largest element | `contracts/player-layout.md` C-P2 |
| FR-002 nothing obscures the video | `contracts/player-layout.md` C-P1; `research.md` R1 |
| FR-003 video does not scroll away | `contracts/player-layout.md` C-P3 |
| FR-004 landscape enlarges the video | `contracts/player-layout.md` C-P4; `research.md` R4 |
| FR-006 rotation does not interrupt playback | `contracts/player-layout.md` C-P6; `research.md` R2, R3 |
| FR-007 larger text never costs the video | `contracts/player-layout.md` C-P8; `research.md` R6 |
| FR-008 mid-song controls within thumb reach | `contracts/player-layout.md` C-P7 |
| FR-009 transport holds a fixed position | `contracts/player-layout.md` C-P7 |
| FR-010 tone control reachable from the control area | `contracts/player-layout.md` C-P1, C-P7 |
| FR-011 next queued song from the control area | `contracts/player-layout.md` C-P7 |
| FR-012 unneeded content leaves the control area | `contracts/player-layout.md` C-P7 |
| FR-013 a named typographic scale exists | `data-model.md` §2; `contracts/typography.md` C-T1 |
| FR-014 no sizes at the point of use | `contracts/typography.md` C-T1; `quickstart.md` Tier 1 |
| FR-015 floor of 13 pt and weight `.regular` | `data-model.md` §1; `contracts/typography.md` C-T3 |
| FR-016 text responds to the system text size | `contracts/typography.md` C-T2; `research.md` R5 |
| FR-018 every screen uses the shared language | `contracts/screen-structure.md` C-S3 |
| FR-019 one navigation container per screen | `contracts/screen-structure.md` C-S1 |
| FR-020 one authoritative place per collection | `contracts/screen-structure.md` C-S2 |
| FR-021 selected and problem colours differ in hue | `data-model.md` §3 |
| FR-022 colour never carries a state alone | `contracts/typography.md` C-T7 |
| FR-023 contrast at least 4.5:1 | `data-model.md` §3; `contracts/typography.md` C-T6 |

### Deferred — 8 requirements

| Requirement | Why deferred |
|---|---|
| FR-005 video grows at a regular width | Story 4 — iPad |
| FR-017 text larger at a regular width | Story 4 — iPad |
| FR-024 labels name the device in hand | Both breaches are correct on iPhone and wrong only on iPad. Recorded in `contracts/screen-structure.md` rather than fixed blind. |
| FR-025 layout follows width, not device | Story 4 — iPad |
| FR-026 queueing does not displace the video | Story 4 — iPad |
| FR-027 readable measure for lists and forms | Story 4 — iPad |
| FR-028 row text and controls grouped | Story 5 — iPad |
| FR-029 Library collections stay visible | Story 5 — iPad |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Principle VIII left unsatisfied for iPad | Owner instructed iPhone first and to set the iPad aside for now. The breach is pre-existing, not introduced here. | Doing the iPad in the same round was rejected because it would delay the reference platform, which is the one in daily use. Shipping a quick capped iPad layout was rejected because Principle VIII explicitly says a layout that merely fits is not a design. |
| Extracting the player host out of `RootView` | R2 requires one `VideoPlayer` at a stable structural position across orientations; that is not achievable while the player is built inline inside the Sing tab's conditional. | Leaving it in place was rejected because the `if showPlayer` swap is itself the identity break that makes rotation tear down the player. |
| A typography token type rather than `Font` constants | `@ScaledMetric` conforms to `DynamicProperty` and only resolves inside a view, so a scaling token cannot be a `static let Font`. | `static let Font.system(size:)` constants were rejected because they do not scale — that is the present defect, and naming it would not fix it. |
