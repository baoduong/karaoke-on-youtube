# Tasks: Professional iPhone and iPad Interface

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04
**Input**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

## Scope

**iPhone only.** Specification Stories 4 and 5, and the eight requirements listed as deferred
in `plan.md`, are not in this list. They stay in the specification unimplemented.

All checkboxes start empty. Nothing here has been built.

## Format: `[ID] [P?] [Story] Description`

- **[P]** — may run in parallel with other `[P]` tasks: different file, no dependency on
  unfinished work.
- **[USn]** — the user story the task serves. Setup, Foundational and Polish carry no story label.

## Path Conventions

Application source is under `Karaoke/Karaoke/`. Tests are under `Karaoke/KaraokeTests/`.
The `.xcodeproj` is generated — run `cd Karaoke && xcodegen generate` after touching
`project.yml`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: make the work measurable before changing anything.

- [X] T001 Extend `Tools/shoot-screens.sh` to capture the player and the tone panel, using the existing `-uiDemoSong <id>` and `-uiDemoEqualizer <bass,mid,treble>` launch arguments, in portrait. Orientation is deliberately not scripted: `xcrun simctl ui` has no orientation option, and rotation around `AVPlayer` must be measured on hardware per Principle III
- [X] T002 Capture the before-baseline to `/tmp/ui-before` with the extended `Tools/shoot-screens.sh`, so every later claim has something to be compared against
- [X] T003 Record the current violation counts in `specs/003-iphone-ipad-interface/quickstart.md` under Tier 1: raw `.font(.system(size:` occurrences (expected 7), nested `NavigationStack` sites (expected 2), favourites render sites (expected 2)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the typography tokens and the player host extraction. Every user story below
depends on at least one of these, and no user story can start until the ones it needs are done.

⚠️ **US1 and US2 both require T009. US1, US2 and US3 all require T004–T008.**

- [X] T004 Add the `TypeToken` struct to `Karaoke/Karaoke/Common/KaraokeTheme.swift` with fields `baseSize: CGFloat`, `weight: Font.Weight`, `design: Font.Design = .default`, `relativeTo: Font.TextStyle`, `maxDynamicTypeSize: DynamicTypeSize? = nil`, enforcing "**MUST be at least 13** at the default text size" and "**MUST NOT be lighter than `.regular`**"
- [X] T005 Add the eight text roles to `Theme.Typography` in `Karaoke/Karaoke/Common/KaraokeTheme.swift` exactly as tabulated in `data-model.md` §2: `displayTitle` 28/.bold/.title/clamp .xxxLarge, `screenTitle` 22/.bold/.title2, `rowTitle` 17/.semibold/.headline, `body` 17/.regular/.body, `bodyEmphasis` 17/.semibold/.body, `secondary` 15/.regular/.subheadline, `caption` 13/.medium/.caption, `timecode` 17/.semibold/.body with `design: .monospaced`
- [X] T006 Add the four glyph roles to `Theme.Typography` in `Karaoke/Karaoke/Common/KaraokeTheme.swift`: `glyphPrimary` 30/.semibold/.title/clamp .xxxLarge, `glyphTransport` 26/.semibold/.title2/clamp .xxxLarge, `glyphStatus` 32/.semibold/.title, `glyphEmpty` 44/.regular/.largeTitle
- [X] T007 Add the resolver to `Karaoke/Karaoke/Common/KaraokeTheme.swift`: a `ViewModifier` holding `@ScaledMetric(wrappedValue:relativeTo:)` that feeds `Font.system(size:weight:design:)`, plus a `View.font(_ token: TypeToken)` extension; apply `.dynamicTypeSize(...max)` when the token declares a clamp. A role **MUST NOT** be exposed as a `static let` of type `Font` — see `contracts/typography.md` C-T2
- [X] T008 Add `Theme.Palette.onAccent` = `rgb(0.055, 0.055, 0.067)` and change `Theme.Palette.contentIssue` from `rgb(0.95, 0.64, 0.22)` to `rgb(1.0, 0.42, 0.20)` in `Karaoke/Karaoke/Common/KaraokeTheme.swift`, then check `mechanismIssue` `rgb(0.91, 0.33, 0.33)` still reads as distinct; if not, move it to `rgb(1.0, 0.27, 0.33)`
- [ ] T009 [P] Extract the player host out of `Karaoke/Karaoke/RootView.swift` into a new `Karaoke/Karaoke/Features/Player/PlayerHostView.swift`, moving the player screen, the starting overlay and their state off the 620-line root view. The Sing tab's `if showPlayer` swap is the identity break that makes rotation tear the player down, so it must not survive this move

---

## Phase 4: User Story 1 - Read the words while singing (Priority: P1) 🎯 MVP

**Goal**: the video is the largest thing on screen, grows when the phone is turned on its
side, and is never covered or dimmed — including while the tone control is being used.

**Independent Test**: start a song and sing it through in a dim room reading only the phone.
Mid-song, open the tone control and adjust all three bands. The words stay readable and fully
visible throughout, in both orientations.

- [ ] T010 [US1] Give `Karaoke/Karaoke/Features/Player/PlayerHostView.swift` an `@Observable` controller owning the single `AVPlayer`, held with `@State` by a host whose own identity never changes
- [ ] T011 [US1] Derive `isLandscape` in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift` from `@Environment(\.verticalSizeClass) == .compact`. `UIDevice.current.orientation` **MUST NOT** be used — it reports `.faceUp` when the phone is laid flat, which would throw the layout out of landscape mid-song (`contracts/player-layout.md` C-P5)
- [ ] T012 [US1] Replace the orientation branch in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift` with `AnyLayout`, keeping exactly one `VideoPlayer` call site at the same structural position in both orientations. It **MUST NOT** appear inside any `if`/`else` or `switch` branch (C-P6)
- [ ] T013 [US1] Remove any `.onDisappear { player.pause() }` attached to the video in `Karaoke/Karaoke/Features/Player/SourceVideoView.swift` and `Karaoke/Karaoke/Features/Player/PlayerVideoStage.swift`, since a layout change would otherwise pause the song
- [ ] T014 [US1] In `Karaoke/Karaoke/Features/Player/PlayerVideoStage.swift`, release the 16:9 aspect constraint when landscape and let the video fill the window, keeping `contentMode: .fit` so the bottom of the frame — where the lyrics are — is never cropped
- [ ] T015 [US1] Hide system chrome in landscape in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift` with `.toolbar(.hidden, for: .navigationBar, .tabBar)`, `.statusBarHidden(true)`, `.persistentSystemOverlays(.hidden)` and `.ignoresSafeArea(edges: .all)`, so the home indicator does not sit over the bottom line of lyrics
- [ ] T016 [US1] Convert `Karaoke/Karaoke/Features/Player/EqualizerView.swift` from a sheet body into an inline panel that participates in layout, and delete `.presentationDetents([.medium, .large])` at line 50
- [ ] T017 [US1] Remove the `.sheet(isPresented: $showEqualizer)` presentation at `Karaoke/Karaoke/RootView.swift:237` and host the inline tone panel inside `PlayerHostView.swift` instead, so opening it shrinks the fitted video rather than covering or dimming it (C-P1)
- [ ] T018 [US1] Apply the same rule to `Karaoke/Karaoke/RootView.swift:209`, the `.sheet(isPresented: $showQualityDetail)` presentation of `QualityDetailView`, so nothing overlays the video while a song is playing
- [ ] T019 [US1] Ensure larger system text never reduces the video in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift`: the control area absorbs the growth via its clamped roles, and the video's area is unchanged between the default size and `.accessibility5` (C-P8)
- [ ] T020 [US1] Verify on a physical iPhone in a dim room: sing a song through reading only the device; open the tone panel mid-song; rotate several times; lay the phone flat face up while in landscape. Record the measured result in `specs/003-iphone-ipad-interface/quickstart.md` against SC-001, SC-002, SC-003

---

## Phase 5: User Story 2 - Work the song one-handed (Priority: P2)

**Goal**: every control the singer needs mid-song sits under the thumb of the hand holding
the phone, and none of them scroll away.

**Independent Test**: hold a real microphone in one hand and the phone in the other. Operate
play/pause, both seeks, next song and the tone control without changing grip.

- [ ] T021 [US2] Create the fixed, non-scrolling control area pinned above the safe area in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift`, holding exactly: play/pause, seek backward, seek forward, next queued song, tone. Each keeps a hit target of at least `Theme.Hit.minimum` (44)
- [ ] T022 [US2] Move the transport out of the scroll view and into the control area in `Karaoke/Karaoke/Features/Player/PlayerView.swift`, so scrolling the content below can no longer carry it off screen
- [ ] T023 [US2] Move the Tone trigger out of the top toolbar in `Karaoke/Karaoke/RootView.swift` and into the control area in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift`; it **MUST NOT** remain reachable only from the navigation bar (C-P7)
- [ ] T024 [US2] Expose the queue's existing advance as a user-initiated action: make `advanceToNextWaiting()` in `Karaoke/Karaoke/Features/Queue/QueueService.swift` callable from the player, without changing its automatic on-finish behaviour
- [ ] T025 [US2] Add the next-song control to the control area in `Karaoke/Karaoke/Features/Player/PlayerView.swift`, calling the action exposed in T024
- [ ] T026 [US2] Move `SuggestionsView` out of the control area in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift` — it is not needed mid-song and must not occupy reachable space (C-P7)
- [ ] T027 [US2] Add `.accessibilityShowsLargeContentViewer()` to every clamped control in the control area in `Karaoke/Karaoke/Features/Player/PlayerView.swift`, which `contracts/typography.md` C-T5 makes mandatory wherever a role is clamped
- [ ] T028 [US2] Verify on a physical iPhone while holding an actual microphone: operate all five mid-song controls one-handed without a grip change, then scroll the content below to its end and confirm the transport has not moved. Record the measured result in `specs/003-iphone-ipad-interface/quickstart.md` against SC-005, SC-006

---

## Phase 6: User Story 3 - A guest can read and work it in a dim room (Priority: P3)

**Goal**: one visual language across every screen — one scale, one navigation bar per screen,
one authoritative favourites list, and no screen that looks like a different app.

**Independent Test**: walk every screen in order. Text roles match between screens, no screen
shows two navigation bars, each collection appears once, and nothing looks foreign.

### Replace the seven hard-coded glyph sizes

- [X] T029 [P] [US3] Replace `.font(.system(size: 30, weight: .semibold))` at `Karaoke/Karaoke/Features/Player/PlayerView.swift:70` with `glyphPrimary`, and `.font(.system(size: 26, weight: .medium))` at line 86 with `glyphTransport`
- [X] T030 [P] [US3] Replace `.font(.system(size: 32, weight: .semibold))` at `Karaoke/Karaoke/Features/Player/PlaybackErrorView.swift:69` and `:148` with `glyphStatus`
- [X] T031 [P] [US3] Replace `.font(.system(size: 44, weight: .light))` at `Karaoke/Karaoke/Common/KaraokeTheme.swift:118` with `glyphEmpty`. This changes the weight from `.light` to `.regular`, which FR-015 requires because thin strokes disappear in a dim room
- [X] T032 [P] [US3] Replace `.font(.system(size: 44, weight: .light))` at `Karaoke/Karaoke/Features/Player/PlayerVideoStage.swift:34` with `glyphEmpty`, the same deliberate `.light` to `.regular` change
- [X] T033 [P] [US3] Replace `.font(.system(size: 40))` at `Karaoke/Karaoke/Features/Search/SearchView.swift:162` with `glyphEmpty`. This unifies 40 on 44; a separate token for a four-point difference would not pay for itself

### Move every screen onto the text roles

- [X] T034 [P] [US3] Replace bare text styles with `Theme.Typography` roles in `Karaoke/Karaoke/Features/Search/SearchView.swift` — song titles to `rowTitle`, channel names to `secondary`, durations to `caption`
- [X] T035 [P] [US3] Replace bare text styles with roles in `Karaoke/Karaoke/Features/Queue/QueueView.swift`, including the state capsule badges, which take `caption`
- [X] T036 [P] [US3] Replace bare text styles with roles in `Karaoke/Karaoke/Features/Library/LibraryView.swift`
- [X] T037 [P] [US3] Replace bare text styles with roles in `Karaoke/Karaoke/Features/Library/SavedSongsView.swift`, including the download-state and storage lines
- [X] T038 [P] [US3] Replace bare text styles with roles in `Karaoke/Karaoke/Features/Settings/SettingsView.swift`
- [X] T039 [P] [US3] Replace bare text styles with roles in `Karaoke/Karaoke/Features/Player/SuggestionsView.swift` and `Karaoke/Karaoke/Features/Player/QualityDetailView.swift`
- [X] T040 [P] [US3] Replace bare text styles with roles in `Karaoke/Karaoke/Common/KaraokeTheme.swift` for `SectionHeading` (`screenTitle`) and `EmptyStateView` (`screenTitle` headline, `body` message)
- [ ] T041 [US3] Apply `timecode` with `design: .monospaced` to the elapsed and remaining time in `Karaoke/Karaoke/Features/Player/PlayerHostView.swift` and to the dB values in `Karaoke/Karaoke/Features/Player/EqualizerView.swift`, so digits do not jitter as they change

### Structure

- [ ] T042 [US3] Remove the nested `NavigationStack` from `Karaoke/Karaoke/Features/Library/LibraryView.swift`, which is already pushed inside the Library tab's stack; the view takes its container from the caller (`contracts/screen-structure.md` C-S1)
- [ ] T043 [US3] Remove the nested `NavigationStack` from `Karaoke/Karaoke/Features/Library/SavedSongsView.swift` and reduce it to a single route, since it is currently reachable from both the Library tab list and a card inside `LibraryView`
- [ ] T044 [US3] Render the favourites list in exactly one place: remove either the inline list on `Karaoke/Karaoke/Features/Library/LibraryView.swift` or the pushed `FavouritesDetailListView` in the same file (C-S2)
- [ ] T045 [US3] Rebuild `Karaoke/Karaoke/Features/Settings/SigningValidityView.swift` on the design system — replace the system `List` and the raw `.red`, `.orange`, `.green`, `.secondary` colours with `Theme` surfaces, palette entries and spacing. Leave the "on your iPhone" wording alone; FR-024 is deferred with the iPad

### Colour

- [ ] T046 [P] [US3] Apply `Theme.Palette.onAccent` to the label of every filled accent control, starting with the play/pause button in `Karaoke/Karaoke/Features/Player/PlayerView.swift` and the primary buttons in `Karaoke/Karaoke/Features/Player/PlaybackErrorView.swift`. White on amber measures about 1.9:1 and fails the 4.5:1 floor
- [ ] T047 [P] [US3] Ensure every state communicated by colour also carries an icon or a text label, in `Karaoke/Karaoke/Features/Player/PlaybackErrorView.swift`, `Karaoke/Karaoke/Features/Queue/QueueView.swift` and `Karaoke/Karaoke/Features/Settings/SettingsView.swift` (C-T7)

### The one automated test

- [ ] T048 [US3] Add a test in `Karaoke/KaraokeTests/` using swift-testing that fails if `.font(.system(size:`, `.font(.custom(`, `.font(Font(` or a bare system text style appears anywhere under `Karaoke/Karaoke/` outside `KaraokeTheme.swift`. Observe it failing against the current tree before the replacements land, then passing after. This is the only part of the feature that can rot silently
- [ ] T049 [US3] Verify on a physical iPhone: walk every screen at the default text size, at `.accessibility5`, and with the display set to greyscale. Measure the contrast of each text and glyph colour against its surface. Record the measured result in `specs/003-iphone-ipad-interface/quickstart.md` against SC-008, SC-009, SC-010

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T050 Capture the after-state to `/tmp/ui-after` with `Tools/shoot-screens.sh` and compare every frame against the `/tmp/ui-before` baseline from T002
- [ ] T051 Confirm the mechanical counts have reached zero in `specs/003-iphone-ipad-interface/quickstart.md` Tier 1: raw font sizes 7 → 0, nested navigation stacks 2 → 0, favourites render sites 2 → 1
- [ ] T052 Open every screen from a running app and operate every control on it — press each one rather than looking at it. The next-song control and the relocated tone control are new and must both be operated. Record the screen-by-screen result in `specs/003-iphone-ipad-interface/quickstart.md` against Quality Gate 7 and SC-014
- [ ] T053 Hand the phone to someone who has not used the app, in a dim room, and time them finding and starting a named song, recording the time in `specs/003-iphone-ipad-interface/quickstart.md` against SC-013
- [ ] T054 Run one continuous session of at least thirty minutes on a physical device with a Bluetooth speaker and a real microphone, rotating the device at least twice, with no crash, no dropout and no advertisement, recording the session in `specs/003-iphone-ipad-interface/quickstart.md`. This is the constitution's release bar
- [ ] T055 Build for a physical device and confirm no new warnings by running `xcodebuild -scheme Karaoke -destination 'generic/platform=iOS' build` from `Karaoke/`, after regenerating with `xcodegen generate` if `Karaoke/project.yml` changed

---

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1 (Setup)            → no dependencies
Phase 2 (Foundational)     → T001-T003 give a baseline; the code work needs nothing
Phase 4 (US1, P1)          → requires T004-T009
Phase 5 (US2, P2)          → requires T004-T009; also T021 sits on the host from T009
Phase 6 (US3, P3)          → requires T004-T008 only. Does NOT require T009.
Phase 7 (Polish)           → requires whichever stories were delivered
```

### User Story Dependencies

- **US1** and **US2** both reshape the player and both depend on T009. They are sequential
  with respect to each other in practice, because T021's control area and T012's `AnyLayout`
  touch the same view. Deliver US1 first.
- **US3** is independent of both. Every task in Phase 6 touches files that US1 and US2 do not
  restructure, with two exceptions — `PlayerView.swift` (T029, T046) and `KaraokeTheme.swift`
  (T031, T040) — which must wait if US1/US2 are in flight on those files.

### Within Each User Story

Work top to bottom. The `[P]` tasks inside Phase 6 may be taken in any order.

### Parallel Opportunities

- **Phase 2**: T009 runs alongside T004-T008 — different files.
- **Phase 6, glyph replacement**: T029-T033 are five different files, all independent.
- **Phase 6, text roles**: T034-T040 are seven different files, all independent.
- **Phase 6, colour**: T046 and T047 are independent of the typography tasks above.

That is **15 tasks marked `[P]`**.

---

## Implementation Strategy

### MVP

**US1 alone is the MVP.** Without a television, reading the words is the app's one job, and
US1 is the only story that addresses it. A singer who cannot reach a control still finishes
the song; a singer who cannot read the next line stops, in front of the room.

Delivering Phase 1 + Phase 2 + Phase 4 gives a phone whose video is the largest thing on
screen, grows when turned sideways, and is never covered or dimmed. That is shippable and
worth shipping on its own.

### Incremental delivery

1. **Phase 1 + 2 + 4** — the words are readable. Ship and sing with it.
2. **Phase 5** — the singer stops needing a second hand.
3. **Phase 6** — the app stops looking assembled.
4. **Phase 7** — the release bar.

Phase 6 can be taken before Phase 5 if the next party matters more than the next rehearsal:
it is independent and more visible to guests.

### What is not here

The iPad. Specification Stories 4 and 5 and the eight deferred requirements in `plan.md`
remain unimplemented, and the iPad keeps the stretched layout that Principle VIII forbids.
That deviation is recorded in `plan.md` under Complexity Tracking; it is a sequencing choice,
not an oversight.
