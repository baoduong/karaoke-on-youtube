# Tasks: Tone Control (Equalizer)

**Feature**: 002-equalizer | **Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/equalizer.md`, `quickstart.md`

**Format**: `[ID] [P?] [Story] Description`

## Status note — read before running `/speckit.implement`

This feature was built before its specification was written, so a list of
empty checkboxes would be a lie and would make `implement` rebuild working
code. Items marked `[x]` were verified in this repository — by reading the
source, by a passing test, or by a measurement recorded in `quickstart.md`.
Items left `[ ]` are genuinely outstanding, and nearly all of them are
measurements that only a physical device and a human ear can settle.

Constitution Principle III governs that split: simulator results do not count
for anything involving audio. The implementation is done; the proof is not.

## Path Conventions

Application code lives under `Karaoke/Karaoke/`, tests under
`Karaoke/KaraokeTests/`. The companion service is not involved in this
feature.

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Amend the project's no-processing rule so a singer-operated tone control is permitted, in `specs/001-youtube-karaoke-ios/spec.md` (FR-009, FR-012, SC-007) and `specs/001-youtube-karaoke-ios/contracts/audio-pipeline.md` invariant 3 — committed separately before any code, as the constitution's Governance section requires

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The value type and the audio plumbing every user story depends on. No story can proceed until these exist.

- [x] T002 Create the `EqualizerSettings` value type in `Karaoke/Karaoke/Audio/EqualizerSettings.swift` with three band gains and an on/off flag, every gain clamped to the range **−12 … +12 dB** on construction **and** on every setter, and a non-finite input coerced to **0**
- [x] T003 Add `isTransparent` to `Karaoke/Karaoke/Audio/EqualizerSettings.swift`, true when the control is off **or** all three bands sit at exactly 0, so a neutral setting is distinguishable from an active one
- [x] T004 Add `headroomGainDB` to `Karaoke/Karaoke/Audio/EqualizerSettings.swift` returning the negative of the largest positive band gain, and **0** when only cutting or when bypassed
- [x] T005 Create the processing tap in `Karaoke/Karaoke/Audio/EqualizerTap.swift`, hosting a three-band filter driven from the render callback, with the real-time-safety note required by Quality Gate 4 recorded in the type's documentation
- [x] T006 Retain the tap's owner in `clientInfo` and release it in the finalize callback in `Karaoke/Karaoke/Audio/EqualizerTap.swift` — an unretained pointer is a use-after-free during teardown
- [x] T007 Add `setEqualizer(_:)` and `isEqualizerAvailable` to the pipeline protocol in `Karaoke/Karaoke/Audio/AudioPipeline.swift`
- [x] T008 Conform the volume test double to the extended protocol in `Karaoke/KaraokeTests/Audio/VolumeTests.swift`

**Checkpoint**: The tone control can be represented, bounded, and carried through the audio layer.

---

## Phase 3: User Story 1 - Fix a song that sounds wrong, without leaving the microphone (Priority: P1) 🎯 MVP

**Goal**: A singer changes the tone of the song currently playing, from the phone, without the music stopping.

**Independent test**: Start any song, raise treble, lower bass, confirm the sound through the PA changes and playback never breaks.

### Implementation for User Story 1

- [x] T009 [US1] Attach the tone control to the item being loaded in `Karaoke/Karaoke/Audio/PlayerPipeline.swift`, choosing the mechanism from what the source offers and leaving the item unprocessed when neither applies
- [x] T010 [US1] Implement `setEqualizer(_:)` in `Karaoke/Karaoke/Audio/PlayerPipeline.swift` so a change applies to the song already playing without reloading it
- [x] T011 [P] [US1] Forward the tone control through `Karaoke/Karaoke/Features/Player/PlaybackSession.swift`
- [x] T012 [US1] Build the tone sheet in `Karaoke/Karaoke/Features/Player/EqualizerView.swift` with an on/off toggle, three labelled band sliders, and signed decibel readouts so a cut reads differently from a boost
- [x] T013 [US1] Add a single-action return to neutral in `Karaoke/Karaoke/Features/Player/EqualizerView.swift`, disabled when all bands already sit at 0
- [x] T014 [US1] Reach the sheet from the player toolbar in `Karaoke/Karaoke/RootView.swift`, with the icon reflecting whether the control is currently doing anything
- [x] T015 [P] [US1] Cover gain clamping in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift`, including above range, below range, in range, the mutating setters, and non-finite input
- [x] T016 [P] [US1] Cover `isTransparent` across all four combinations of on/off and flat/moved in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift`
- [x] T017 [P] [US1] Cover headroom across boost-only, cut-only, mixed, bypassed, and maximum boost in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift`
- [x] T018 [P] [US1] Verify the tap attaches to a file-based source using a generated tone, in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift`, so a silent regression in attachment fails the suite
- [x] T019 [P] [US1] Render the sheet in both availability states in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift` — a view that compiles can still trap at run time
- [ ] T020 [US1] Measure SC-001 on the physical device through the Bluetooth PA: a band change audible within **200 ms** with no click, gap, or dropout; record the result in `specs/002-equalizer/quickstart.md`
- [ ] T021 [US1] Measure SC-002 on the physical device: with the control off or neutral, capture the output and confirm it matches the source apart from level; record the result in `specs/002-equalizer/quickstart.md`
- [ ] T022 [US1] Measure SC-005 on the physical device against a track mastered near maximum level, sweeping band combinations and confirming no audible distortion at any of them; record the result in `specs/002-equalizer/quickstart.md`
- [ ] T023 [US1] Measure SC-003: time a singer finding the control, changing the sound, and returning to the song, confirming under **15 seconds** with playback uninterrupted; record the result in `specs/002-equalizer/quickstart.md`
- [ ] T024 [US1] Judge the chosen band centres by ear on the real PA and adjust the constants in `Karaoke/Karaoke/Audio/EqualizerSettings.swift` if treble reads as harsh or bass as boomy — they were reasoned, never heard

**Checkpoint**: User Story 1 is independently usable. Everything above except the measurements is in place.

---

## Phase 4: User Story 2 - Set it once, not every song (Priority: P2)

**Goal**: A setting found once survives the next song and the next launch.

**Independent test**: Adjust the tone, play a different song, confirm it still applies; quit and relaunch, confirm it survived.

### Implementation for User Story 2

- [x] T025 [US2] Add the four stored fields to `Karaoke/Karaoke/Store/Models/PerformanceSettings.swift` — on/off plus one gain per band — each declared with an inline default so adding them to an existing store is a lightweight migration rather than a launch failure
- [x] T026 [US2] Expose one computed `equalizer` accessor on `Karaoke/Karaoke/Store/Models/PerformanceSettings.swift` that clamps by delegating to the value type, so the bound is stated in exactly one place
- [x] T027 [US2] Load the stored setting at launch and push it to the audio layer in `Karaoke/Karaoke/RootView.swift`
- [x] T028 [US2] Persist on every change from the sheet in `Karaoke/Karaoke/RootView.swift`
- [x] T029 [P] [US2] Cover the storage round trip and the defaults of a fresh record in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift`
- [ ] T030 [US2] Cover SC-008 directly: write an out-of-range gain into the store bypassing the public accessor, then confirm the value reaching the audio layer is still inside **−12 … +12 dB**, in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift` — the existing test only exercises the clamping accessor, so the corrupted-store path is unproven
- [ ] T031 [US2] Measure SC-004 on the physical device: ten consecutive launches with the setting unchanged; record the result in `specs/002-equalizer/quickstart.md`

**Checkpoint**: The setting persists across songs and launches.

---

## Phase 5: User Story 3 - Know when it cannot be applied (Priority: P3)

**Goal**: When the system refuses the tone control for a song, the singer is told rather than given a control that does nothing.

**Independent test**: Play a song on a path the control cannot reach, open the sheet, confirm it says so plainly.

### Implementation for User Story 3

- [x] T032 [US3] Track whether the control actually attached, per loaded item, in `Karaoke/Karaoke/Audio/PlayerPipeline.swift`, and expose it as `isEqualizerAvailable`
- [x] T033 [US3] Show an explicit notice in `Karaoke/Karaoke/Features/Player/EqualizerView.swift` when the control is unavailable, stating that the saved settings are kept and will apply to the next song that accepts them
- [x] T034 [US3] Report nothing as available before a source is loaded, covered in `Karaoke/KaraokeTests/Audio/EqualizerTests.swift`
- [ ] T035 [US3] Measure SC-007 across a real song set on the physical device: for every song where the control cannot be applied the notice appears, and the count of songs where it appears functional but does nothing is **zero**; record the result in `specs/002-equalizer/quickstart.md`

**Checkpoint**: Refusal is visible, never silent.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T036 Reduce `FR-043` and `SC-015` in `specs/001-youtube-karaoke-ios/spec.md` to cross-references pointing at this feature, so the same obligation is stated once rather than twice
- [ ] T037 Measure SC-006 on the physical device: a two-hour session with the control active, confirming no dropout and no unbounded memory growth, and record the result in `specs/002-equalizer/quickstart.md` — a leak in the per-item audio graph would surface here and nowhere else
- [ ] T038 Re-check the Debug-build caveat recorded in `specs/002-equalizer/contracts/equalizer.md`: confirm on device that the release build behaves identically to the debug build under sustained playback, or amend the contract if it does not

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)** — must precede everything. The constitution requires the specification conflict be resolved before the code, in its own change.
- **Phase 2 (Foundational)** — blocks all user stories.
- **Phase 3 (US1)** — depends on Phase 2 only.
- **Phase 4 (US2)** — depends on Phase 2; independent of US1's measurements.
- **Phase 5 (US3)** — depends on Phase 2 and on T009, which is what decides availability.
- **Phase 6 (Polish)** — last.

### User Story Dependencies

US1, US2 and US3 are independent of one another once Phase 2 is done. US3's
notice is only meaningful once T009 exists, but that is a foundational
attachment task, not a dependency on US1 being finished.

### Within Each User Story

Value type → audio layer → persistence → interface → tests → device
measurement. The measurements come last because they depend on a signed
build running on hardware.

### Parallel Opportunities

All five test tasks in Phase 3 (T015–T019) touch one file but independent
suites and were written together. T011 is parallel with T009 and T010 because
it edits a different file.

The device measurements T020–T024, T031, T035 and T037 can be gathered in a
single session at one party rather than one sitting each — they all need the
same setup: a signed build, the PA, and someone singing.

---

## Parallel Example: User Story 1

```text
T009, T010  (PlayerPipeline.swift)       ─┐
T011        (PlaybackSession.swift)      ─┼─ different files, run together
T012, T013  (EqualizerView.swift)        ─┘

then T015, T016, T017, T018, T019 as one test-writing pass
then T020–T024 as one device session
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

US1 alone is the feature: a singer can fix a song that sounds wrong without
walking to the speaker. US2 removes a chore and US3 protects trust, but
neither is what the feature is for.

### Incremental Delivery

Already delivered in this order: Phase 1 as its own commit, then Phase 2 and
US1 together, then US2 and US3, then the render check. What remains is a
single device session and three documentation cleanups.

### What is actually left

Of 38 tasks, 27 are complete and verified. The 11 open items are 8 device
measurements, 1 test closing a real gap in SC-008 coverage, and 2
documentation corrections. No application code is known to be missing.

---

## Notes

- Suite at the time of writing: **299 tests in 53 suites**, green on both
  installed runtimes, with zero crash-restarts in the log. Counting passes
  alone is not enough here — an earlier build reported "243 tests passed"
  while crashing the host partway through.
- The attachment behaviour differs by platform version and by source kind.
  The measured matrix is recorded in `quickstart.md` and in the attachment
  suite's own documentation; do not assume it, re-measure it if the platform
  moves.
- T024 is the task most likely to be skipped and most likely to matter. The
  band centres were chosen by reasoning about what a PA does to a karaoke
  mix. Nobody has yet listened.
