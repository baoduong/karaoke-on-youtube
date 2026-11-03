---

description: "Task list for YouTube-Sourced Karaoke App for iPhone/iPad"
---

# Tasks: YouTube-Sourced Karaoke App for iPhone/iPad

**Input**: Design documents from `/specs/001-youtube-karaoke-ios/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: Test tasks ARE included. Not as a default — [`.specify/memory/constitution.md`](../../.specify/memory/constitution.md) Principle IV makes tests mandatory for logic that fails quietly (rendition ranking, error classification, lyric timing, queue transitions, cache accounting, parsers), and each contract names its own test scope. Tests are **excluded** for SwiftUI layout and audio graph wiring, which Principle III requires to be verified on a device instead.

**Organization**: Grouped by user story so each is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1…US5)
- Exact file paths included in every task

## Path Conventions

Single iOS app target with internal module directories, per plan.md's Structure Decision:

- App source: `Karaoke/Karaoke/`
- Tests: `Karaoke/KaraokeTests/`
- Companion service (runs on the singer's own machine, outside the app target): `Tools/companion-service/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton and the configuration that enforces two non-negotiables — background audio on, microphone off.

- [x] T001 Create Xcode project `Karaoke/Karaoke.xcodeproj` with a single iOS app target named Karaoke, deployment target iOS 17.0, per plan.md Technical Context
- [x] T002 Enable Swift 6 language mode with strict concurrency checking in the Karaoke target build settings
- [x] T003 Enable Background Modes → Audio capability and confirm `UIBackgroundModes` contains `audio` in `Karaoke/Karaoke/Info.plist` (required by FR-015)
- [x] T004 Verify `Karaoke/Karaoke/Info.plist` contains **no** `NSMicrophoneUsageDescription` key — its absence is the enforcement mechanism for FR-010 and SC-003
- [x] T005 [P] Add YouTubeKit (MIT, github.com/alexeichhorn/YouTubeKit, pin 0.4.10 or later) as a Swift Package dependency of the Karaoke target
- [x] T006 [P] Create the directory skeleton `Karaoke/Karaoke/{Sources,Audio,Lyrics,Suggestions,Store,Features,Common}/` per plan.md Source Code structure
- [x] T007 [P] Create the test target `Karaoke/KaraokeTests/` with Swift Testing and subdirectories `{Sources,Audio,Lyrics,Suggestions,Store,Fixtures}/`
- [x] T008 [P] Add SwiftLint configuration at `Karaoke/.swiftlint.yml` and wire it as a build phase so the no-new-warnings release gate is enforceable

---

## Phase 2: Measurement Spikes (Blocking Prerequisites)

**Purpose**: Convert research.md's **[prior]** findings into measurements. These are blocking because each one can invalidate work built on top of it. research.md's rule applies: no **[prior]** may be cited as evidence until its spike has run.

**⚠️ CRITICAL**: T009 and T010 require the actual Bluetooth PA speaker. Simulator results do not count (Principle III).

- [ ] T009 **Spike S5** — measure Bluetooth route delay: build a throwaway target that plays a tone with a sharp transient, read the session's reported output latency, record video capturing screen and room sound together, and write the measured-vs-reported delay to `specs/001-youtube-karaoke-ios/research.md` R4. This runs first because Bluetooth is the only supported route, so a missing compensation is wrong for every song
- [ ] T010 **Spike S0** — determine which codec the Bluetooth link negotiates with the actual PA speaker, capture the same song over Bluetooth and over a cable, and record the measured quality gap in `specs/001-youtube-karaoke-ios/research.md` R0. This decides how honest FR-014's quality disclosure must be and whether T012 deserves effort
- [ ] T011 **Spike S7** — on a physical device confirm three things and record results in `specs/001-youtube-karaoke-ios/research.md` R6: audio continues when backgrounded and screen-locked; an HTTP request to a LAN address succeeds; observed code-signature validity matches expectation
- [ ] T012 **Spike S1** — fetch one itag 251 (Opus/WebM) and one itag 140 (AAC/M4A) stream, attempt to open each with the platform asset APIs, and if Opus fails test whether remuxing without re-encoding yields a playable asset; record the outcome in `specs/001-youtube-karaoke-ios/research.md` R1
- [ ] T013 **Spike S3** — resolve a stream address, record its declared expiry, probe at intervals until refused, and record the observed lifetime and the chosen safety margin in `specs/001-youtube-karaoke-ios/research.md` R3
- [x] T014 [P] **Spike S6** — DONE 2026-11-03. `/api/get` returned 200 on 3 of 3 attempts (~0.4 s each), no rate limiting; the planning-time 503 was transient. `/api/get-cached` does not exist (404). Bigger finding: **0 of 20 results for a popular track carried word-level timing**, so line-level highlight is the feature and word-level is opportunistic. Recorded in research.md R5
- [x] T015 [P] **Spike S8** — DONE 2026-11-03. YouTubeKit 0.4.10 has **zero** watch-next support (no matches for `watchNext`, `relatedVideo`, `secondaryResults`, `compactVideoRenderer`, `autoplay`, `endscreen`; public API is metadata/videoID/checkAvailability/ageRestricted/streams/livestreams). **Decision: do not build `upstreamRelated`; T095 is cancelled.** Recorded in research.md R8

**Checkpoint**: All measurements recorded. research.md contains no uncited **[prior]** blocking downstream work.

---

## Phase 3: Foundational (Blocking Prerequisites)

**Purpose**: The store, the entity models, and the source-resolution boundary. Every user story depends on these.

**⚠️ CRITICAL**: No user story work begins until this phase completes.

### Persistence models

- [x] T016 [P] Create the `Song` SwiftData model in `Karaoke/Karaoke/Store/Models/Song.swift` with fields `id: String` (primary key), `title: String`, `channelName: String`, `durationSeconds: Int`, `thumbnailURL: URL?`, `firstSeenAt: Date`, `lastPlayedAt: Date?`, `playCount: Int` defaulting to 0
- [x] T017 [P] Implement `Song` validation in `Karaoke/Karaoke/Store/Models/Song.swift`: reject malformed `id` at parse time and never persist it; drop results where `durationSeconds` is not `> 0`; flag but do **not** reject `durationSeconds > 3600`; require `title` and `channelName` non-empty after trimming
- [x] T018 [P] Create the `SavedSong` SwiftData model in `Karaoke/Karaoke/Store/Models/SavedSong.swift` with `songID: String` (primary key — one saved copy per Song), `fileRelativePath: String` (relative, not absolute, so it survives reinstalls), `container`, `codec`, `averageBitrateBps: Int?`, `byteSize: Int64`, `savedAt: Date`, `state: SaveState`, `downloadedBytes: Int64`, `lastError: String?`
- [x] T019 [P] Create the `Favourite` SwiftData model in `Karaoke/Karaoke/Store/Models/Favourite.swift` with `songID: String` (primary key — a Song is favourited at most once) and `addedAt: Date`, sorted newest first by default
- [x] T020 [P] Create the `QueueEntry` SwiftData model in `Karaoke/Karaoke/Store/Models/QueueEntry.swift` with `id: UUID` (own identity — the same Song may appear twice), `songID: String`, `position: Int` (zero-based, contiguous and unique within the Queue), `addedAt: Date`, `state: QueueEntryState` (`waiting`, `current`, `played`, `skipped`, `failed`)
- [x] T021 [P] Create the `PerformanceSettings` singleton model in `Karaoke/Karaoke/Store/Models/PerformanceSettings.swift` with exactly three fields: `outputVolume: Double` default 1.0 range 0.0…1.0; `manualLyricsOffsetMs: Int` default 0 range −2000…+2000; `lyricsFontScale: Double` default 1.0 range 0.5…3.0. No vocal fields, no pitch or tempo fields
- [x] T022 [P] Create the `LyricsTrack`, `LyricsLine`, and `LyricsWord` models in `Karaoke/Karaoke/Store/Models/LyricsTrack.swift` per data-model.md, including `hasWordTiming: Bool` and `globalOffsetMs: Int` defaulting to 0
- [x] T023 Implement range clamping on read **as well as** write for every numeric field in `Karaoke/Karaoke/Store/Models/PerformanceSettings.swift` — a corrupted or hand-edited store must not push an out-of-range value at a party PA, which is a speaker-damage and hearing-safety concern

### Store infrastructure

- [x] T024 Configure the SwiftData `ModelContainer` in `Karaoke/Karaoke/Store/MediaStore.swift` and expose the app's media directory path for saved audio files (audio bytes stay out of the database)
- [x] T025 Implement `StoreReconciler` in `Karaoke/Karaoke/Store/StoreReconciler.swift` enforcing data-model.md's cross-entity invariants at launch: repair orphaned references (invariant 1); delete Songs not referenced by a Favourite, QueueEntry, or SavedSong (invariant 2); cascade LyricsTrack and SavedSong file deletion (invariant 3); reconcile SavedSong records against files with the file system authoritative for existence and the record for metadata; move any `pending` or `downloading` entry out of its transient state

### SourceProvider boundary

- [x] T026 [P] Define the `SourceProvider` protocol in `Karaoke/Karaoke/Sources/SourceProvider.swift` with `identifier`, `healthCheck()`, `search(query:limit:)`, `metadata(for:)`, `audioRenditions(for:)`, and `streamAddress(for:itag:)` exactly as specified in contracts/source-provider.md
- [x] T027 [P] Define the full `SourceError` taxonomy and `ResolutionStage` enum in `Karaoke/Karaoke/Sources/SourceError.swift`, keeping the three groups separate: content-side (`notFound`, `private_`, `removed`, `regionBlocked`, `ageRestricted`, `liveStreamUnsupported`, `noAudioRenditions`), mechanism-side (`resolutionFailed`, `upstreamContractChanged`, `cipherFailure`), environment (`offline`, `timeout`, `rateLimited`, `quotaExhausted`), plus caller-fault cases
- [x] T028 [P] Define `AudioRendition`, `StreamAddress`, `Container`, and `Codec` types in `Karaoke/Karaoke/Sources/RenditionTypes.swift`, with `StreamAddress` carrying `expiresAt`, `resolvedAt`, and `supportsRangeRequests`
- [x] T029 Implement `SourceReference` parsing in `Karaoke/Karaoke/Sources/SourceReference.swift` accepting a full URL, a shortened URL, or a bare identifier, normalising to `SongID`, and returning `malformedReference` without any network call for unparseable input
- [x] T030 Implement the pure rendition ranking function in `Karaoke/Karaoke/Sources/RenditionSelection.swift` following data-model.md's Selection Rule exactly: discard renditions where `isDecodableOnDevice` is false and fail with *unavailable format* (distinct from *unavailable song*) if the set empties; rank by `averageBitrateBps` descending; break ties by codec preference from research.md R1; then `channelCount` descending; then `itag` ascending for determinism. Must be a pure function so SC-004 is verifiable offline
- [x] T031 Implement on-device decodability detection in `Karaoke/Karaoke/Sources/DecodabilityProbe.swift` by querying the platform's decoder support rather than a hardcoded codec list, so the answer stays correct across OS versions (uses T012's finding)
- [x] T032 Implement `OnDeviceSourceProvider` in `Karaoke/Karaoke/Sources/OnDeviceSourceProvider.swift` wrapping YouTubeKit, mapping every upstream outcome onto the `SourceError` taxonomy and tagging each `resolutionFailed` with its `ResolutionStage`
- [x] T033 Implement `SourceProviderRouter` as an actor in `Karaoke/Karaoke/Sources/SourceProviderRouter.swift`: try providers in order, skip unhealthy ones, **return content-side errors immediately without falling through** (a private song is private for every provider), fall through on mechanism-side and environment errors, and record which provider served each request
- [x] T034 Implement address staleness handling in `Karaoke/Karaoke/Sources/StreamAddressCache.swift` using the safety margin measured in T013 — refresh **before** expiry, never after a failure, so FR-007 produces no audible gap. Never persist an address and never log it in full (data-model invariant 4)
- [x] T035 Implement local diagnostic logging for mechanism-side errors in `Karaoke/Karaoke/Common/DiagnosticLog.swift` recording stage, timestamp, and a redacted detail string, with `StreamAddress.url` excluded from every log, error message, and persisted record

### Foundational tests

- [x] T036 [P] Write reference-parsing tests in `Karaoke/KaraokeTests/Sources/SourceReferenceTests.swift` covering every accepted URL and identifier shape plus malformed input yielding `malformedReference` with no network call
- [x] T037 [P] Write the **error classification test** in `Karaoke/KaraokeTests/Sources/ErrorClassificationTests.swift` mapping a table of recorded upstream responses to the correct `SourceError` case. contracts/source-provider.md names this the highest-value test in the project: misclassifying a broken parser as "song unavailable" hides breakage until the whole library appears empty
- [x] T038 [P] Write rendition parsing and ranking tests in `Karaoke/KaraokeTests/Sources/RenditionSelectionTests.swift` using recorded format payloads, covering absent bitrate, unknown codec, duplicate itag (must fail resolution rather than silently pick one), and the empty-after-filtering case
- [x] T039 [P] Write router behaviour tests in `Karaoke/KaraokeTests/Sources/SourceProviderRouterTests.swift` asserting content-side errors stop the chain, mechanism-side errors fall through, unhealthy providers are skipped, and the serving provider is attributed correctly
- [x] T040 [P] Write expiry parsing tests in `Karaoke/KaraokeTests/Sources/StreamAddressTests.swift` for addresses with and without an explicit expiry, confirming the absent case defaults conservatively
- [x] T041 [P] Write settings clamping tests in `Karaoke/KaraokeTests/Store/PerformanceSettingsTests.swift` asserting out-of-range values are clamped on read as well as write for all three fields
- [x] T042 [P] Write store reconciliation tests in `Karaoke/KaraokeTests/Store/StoreReconcilerTests.swift` covering orphaned records, orphaned files, unreferenced Song cleanup, and transient-state recovery
- [x] T043 [P] Record upstream response fixtures into `Karaoke/KaraokeTests/Fixtures/` so the suite never touches the live network — a test suite that depends on YouTube being up fails for the wrong reasons

**Checkpoint**: Store, models, and the resolution boundary are complete and tested. User story work can begin.

---

## Phase 4: User Story 1 - Find and play a karaoke track (Priority: P1) 🎯 MVP

**Goal**: Search a song by name, select it, and hear it ad-free through the Bluetooth PA speaker at the best rendition the device can decode.

**Independent Test**: Pair the speaker, launch the app cold, search a known karaoke title, select the first result, confirm audio within 5 s of selection and 30 s of launch, and confirm no advertisement appears before, during, or after (quickstart.md Scenario 1).

### AudioPipeline — playback only, no processing graph

- [ ] T044 [P] [US1] Define the `AudioPipeline` protocol in `Karaoke/Karaoke/Audio/AudioPipeline.swift` with `prepare()`, `stop()`, `load(source:)`, `play()`, `pause()`, `seek(to:)`, `position`, `setVolume(_:)`, `outputRoute`, and `events`. Include **no** microphone member and **no** pitch or tempo member — both absences are the contract
- [ ] T045 [P] [US1] Define `AudioSource`, `PlaybackPosition`, `OutputRoute`, `RouteKind`, `AudioPipelineEvent`, and `AudioError` in `Karaoke/Karaoke/Audio/AudioTypes.swift` per contracts/audio-pipeline.md. `PlaybackPosition` carries only `seconds` and `isValid` — no rate conversion field, since playback rate is always 1.0
- [ ] T046 [US1] Implement `AudioSessionController` in `Karaoke/Karaoke/Audio/AudioSessionController.swift` configuring a **playback-only** session category on every code path, with no conditional that could configure a record-capable session
- [ ] T047 [US1] Implement `PlayerPipeline` in `Karaoke/Karaoke/Audio/PlayerPipeline.swift` using the platform's standard media player — no audio engine, no processing graph, no custom buffering, no render callbacks. Handles both `.remote(StreamAddress)` and `.local(URL)` sources identically in quality
- [ ] T048 [US1] Implement ramped volume application in `Karaoke/Karaoke/Audio/PlayerPipeline.swift` so a change is audible within 200 ms with no click, and apply **nothing else** to the samples — no resampling, no normalisation, no EQ, no "enhancement" (FR-011, FR-012, SC-007)
- [ ] T049 [US1] Implement `OutputRouteMonitor` in `Karaoke/Karaoke/Audio/OutputRouteMonitor.swift` publishing `kind`, `isExternal`, `outputLatencyMs` (from the live route, using T009's calibration), and `degradesQuality` set true for any re-encoding wireless route
- [ ] T050 [US1] Implement external-output-lost handling in `Karaoke/Karaoke/Audio/PlayerPipeline.swift`: when the Bluetooth link drops, **pause** and emit `externalOutputLost` rather than falling through to the device's own speaker at party volume (FR-018)
- [ ] T051 [US1] Implement stall handling in `Karaoke/Karaoke/Audio/PlayerPipeline.swift` emitting `stalled` and provably **not** triggering stream re-resolution — a radio problem is not a stream problem, and re-resolving makes it worse while spending quota

### Search and metadata

- [ ] T052 [P] [US1] Implement `DataAPISearchProvider` in `Karaoke/Karaoke/Sources/DataAPISearchProvider.swift` calling the YouTube Data API v3 search endpoint for search and metadata only, with the API key read from local configuration
- [ ] T053 [US1] Implement submit-driven search with per-session query caching in `Karaoke/Karaoke/Features/Search/SearchViewModel.swift` — never keystroke-driven, because the search allowance is **100 calls per day** (research.md R2, verified) and search-as-you-type would exhaust it in minutes
- [ ] T054 [US1] Implement direct-reference entry in `Karaoke/Karaoke/Features/Search/SearchViewModel.swift` so a pasted link or bare identifier resolves via `SourceReference` without a search call (FR-002)

### Playback session and UI

- [ ] T055 [US1] Implement the `PlaybackSession` in-memory state holder in `Karaoke/Karaoke/Features/Player/PlaybackSession.swift` with `songID`, `selectedRendition`, `positionSeconds`, `durationSeconds`, `state`, `outputRoute`, `outputLatencyMs`, `isExternalOutputPresent`, `lastError`, and `performedSongIDs`. Never persisted
- [ ] T056 [US1] Implement the session state machine in `Karaoke/Karaoke/Features/Player/PlaybackSession.swift` per data-model.md: `idle → resolving → buffering → playing`, with `resolving → failed` carrying which kind of failure it was, and a stale address triggering a silent re-resolve that preserves position without visibly leaving `playing`
- [ ] T057 [US1] Build the search results view in `Karaoke/Karaoke/Features/Search/SearchView.swift` showing title, channel, and duration per result (FR-001)
- [ ] T058 [US1] Build the player view in `Karaoke/Karaoke/Features/Player/PlayerView.swift` with transport controls, position, volume, and the active route indicator
- [ ] T059 [US1] Implement the quality detail disclosure in `Karaoke/Karaoke/Features/Player/QualityDetailView.swift` reporting the selected rendition's format, codec, and bitrate on request (FR-005), and surfacing `degradesQuality` so the app does not advertise quality the Bluetooth link discards (FR-014)
- [ ] T060 [US1] Implement error presentation in `Karaoke/Karaoke/Features/Player/PlaybackErrorView.swift` wording content-side failures as the singer's situation and mechanism-side failures distinctly, per FR-008
- [ ] T061 [US1] Increment `Song.playCount` and set `lastPlayedAt` only when playback passes the halfway point, not on mere selection, in `Karaoke/Karaoke/Features/Player/PlaybackSession.swift`

### Tests for User Story 1

- [ ] T062 [P] [US1] Write the session-category test in `Karaoke/KaraokeTests/Audio/AudioSessionControllerTests.swift` asserting playback-only on every path through `prepare` — this is what keeps FR-010 true as the code changes
- [ ] T063 [P] [US1] Write volume clamping tests in `Karaoke/KaraokeTests/Audio/VolumeTests.swift` asserting out-of-range values are clamped before reaching the player
- [ ] T064 [P] [US1] Write route classification tests in `Karaoke/KaraokeTests/Audio/OutputRouteTests.swift` mapping a table of route descriptors to the correct `kind`, `isExternal`, `degradesQuality`, and delay
- [ ] T065 [P] [US1] Write external-output-lost tests in `Karaoke/KaraokeTests/Audio/OutputLossTests.swift` asserting a dropped route produces a pause and the event, never continued playback
- [ ] T066 [P] [US1] Write stall-handling tests in `Karaoke/KaraokeTests/Audio/StallTests.swift` asserting a stall produces `stalled` and provably does **not** trigger re-resolution
- [ ] T067 [P] [US1] Write seek bounds tests in `Karaoke/KaraokeTests/Audio/SeekTests.swift` asserting out-of-range seeks yield `seekOutOfBounds` rather than clamping silently

### Device validation for User Story 1

- [ ] T068 [US1] Run quickstart.md Scenario 1 (search to sound) on a physical device with the Bluetooth PA speaker and record pass/fail against SC-001, SC-002, SC-006
- [ ] T069 [US1] Run quickstart.md Scenario 2 (no microphone) and confirm no permission prompt appears anywhere and the app never registers microphone access (SC-003)
- [ ] T070 [US1] Run quickstart.md Scenario 3 (quality honesty) against a 20-song sample, comparing the app's reported choice against the renditions actually available (SC-004)
- [ ] T071 [US1] Run quickstart.md Scenario 4 (volume only, no processing) including the output capture that proves the audio is the decoded source with level applied and nothing else (SC-007)

**Checkpoint**: The app is useful. Search → select → play works ad-free through the PA speaker. Everything after this is enhancement.

---

## Phase 5: User Story 3 - Follow the words (Priority: P2)

**Goal**: Display the words in step with the sound the room hears, legibly at room distance.

**Independent Test**: Play a song with a synchronized text track over Bluetooth, record video capturing screen and room sound, and confirm alignment within 150 ms throughout including after three seeks (quickstart.md Scenario 5).

**Sequenced before User Story 2** per plan.md: the delay compensation is the harder problem and the one the Bluetooth decision made unavoidable.

### LyricsProvider boundary

- [ ] T072 [P] [US3] Define the `LyricsProvider` protocol, `LyricsQuery`, and `LyricsError` in `Karaoke/Karaoke/Lyrics/LyricsProvider.swift`. `LyricsQuery.durationSeconds` is **required, not optional** — matching on title alone returns the wrong song often enough that the duration check is the difference between a useful feature and a confusing one. No error case means "not found"; absence is `nil`
- [ ] T073 [US3] Implement `LRCLIBProvider` in `Karaoke/Karaoke/Lyrics/LRCLIBProvider.swift` against lrclib.net, disabled until the singer opts in, using the lookup path decided by T014, and reading the response's `hasWordSync` flag to choose rendering mode before parsing
- [ ] T074 [US3] Implement `LyricsParser` in `Karaoke/Karaoke/Lyrics/LyricsParser.swift` with all five rejection rules from contracts/lyrics-provider.md: line start times not strictly increasing; a line's end time not greater than its start or exceeding the next line's start; word start times not strictly increasing or outside the enclosing line's bounds; last start time exceeding song duration beyond a small tolerance; empty or untimed track. Empty text on a timed line is **not** a rejection — it is a legitimate instrumental-gap marker
- [ ] T075 [US3] Implement `LyricsTimeline` as a pure lookup in `Karaoke/Karaoke/Lyrics/LyricsTimeline.swift` with effective time = position − `outputLatencyMs` + `globalOffsetMs` + `manualLyricsOffsetMs`. **The output-latency subtraction is the point of this task.** The player reports what was dispatched; the Bluetooth speaker emits it a sixth of a second later. Because Bluetooth is the only supported route, omitting this is wrong for every song
- [ ] T076 [US3] Implement binary search with previous-index hinting in `Karaoke/Karaoke/Lyrics/LyricsTimeline.swift` so lookup at display refresh rate performs no allocation and no I/O and runs better than linear over lines

### Lyrics UI

- [ ] T077 [US3] Build the lyrics display in `Karaoke/Karaoke/Features/Lyrics/LyricsView.swift` driven by a display-refresh callback that **asks** the player for position — never a timer that keeps its own position, which is how karaoke displays drift
- [ ] T078 [US3] Implement current-line and current-word highlighting with read-ahead in `Karaoke/Karaoke/Features/Lyrics/LyricsView.swift` — a display showing only the current line is useless for singing
- [ ] T079 [US3] Implement text scaling bound to `lyricsFontScale` (range 0.5…3.0) in `Karaoke/Karaoke/Features/Lyrics/LyricsView.swift`, legible at room viewing distance on iPad (FR-024)
- [ ] T080 [US3] Implement the manual display-versus-audio trim control in `Karaoke/Karaoke/Features/Settings/LyricsOffsetView.swift` bound to `manualLyricsOffsetMs` (range −2000…+2000), added **on top of** the automatic route delay, with reset to 0 restoring automatic behaviour (FR-020)
- [ ] T081 [US3] Build the video display path in `Karaoke/Karaoke/Features/Lyrics/SourceVideoView.swift` for sources that carry the words in the image, kept in step with the audio (FR-021)
- [ ] T082 [US3] Implement the lyrics opt-in toggle in `Karaoke/Karaoke/Features/Settings/SettingsView.swift`, defaulting to off so no network request for text is made until the singer enables it

### Tests for User Story 3

- [ ] T083 [P] [US3] Write parser tests in `Karaoke/KaraokeTests/Lyrics/LyricsParserTests.swift` for well-formed line-level and word-level inputs, using **synthetic placeholder text only** — no real song text is committed to this repository
- [ ] T084 [P] [US3] Write validation tests in `Karaoke/KaraokeTests/Lyrics/LyricsValidationTests.swift` exercising each of the five rejection rules, with the duration-mismatch rule covered explicitly since it is what prevents the wrong song's words appearing
- [ ] T085 [P] [US3] Write lookup tests in `Karaoke/KaraokeTests/Lyrics/LyricsTimelineTests.swift` at boundary times: before the first line, exactly on a boundary, mid-word, in a gap, and after the last line
- [ ] T086 [P] [US3] Write seek-correction tests in `Karaoke/KaraokeTests/Lyrics/LyricsSeekTests.swift` asserting a jump to an arbitrary position returns the correct index on the **first** lookup with no intermediate wrong value
- [ ] T087 [P] [US3] Write route-delay compensation tests in `Karaoke/KaraokeTests/Lyrics/LyricsDelayTests.swift` asserting that with a non-zero route delay the lookup returns the line and word that will be *heard* at that moment, not the one being dispatched, across a table of delay values including zero
- [ ] T088 [P] [US3] Write offset tests in `Karaoke/KaraokeTests/Lyrics/LyricsOffsetTests.swift` asserting a non-zero global offset and manual trim each shift the resolved position by exactly that amount

### Device validation for User Story 3

- [ ] T089 [US3] Run quickstart.md Scenario 5 over the Bluetooth speaker with video capture and measure alignment against the 150 ms budget including three seeks (SC-008). Take the cable measurement as a calibration reference only
- [ ] T090 [US3] Verify the manual trim moves the highlight by exactly the amount set, and record this speaker's measured-versus-reported delay

**Checkpoint**: Words follow the sound the room actually hears. The project's hardest success criterion is met.

---

## Phase 6: User Story 2 - Know what to sing next (Priority: P2)

**Goal**: Offer sensible next songs so the party keeps moving without someone hunting through a search box between every number.

**Independent Test**: Play six songs and confirm suggestions appear within 3 s, that nothing already sung this session is offered, that each suggestion states where it came from, and that suggestions still appear with the network disabled (quickstart.md Scenario 6).

**Design note**: The platform's related-videos parameter no longer exists and search is capped at 100 calls per day, so local strategies carry this feature and upstream data is an optional extra.

- [ ] T091 [P] [US2] Define the `RecommendationProvider` and `RecommendationEngine` protocols, the `Suggestion` type, `SuggestionStrategy` enum (`upstreamRelated`, `sameChannel`, `coOccurrence`, `history`, `favourite`), and `RecommendationError` in `Karaoke/Karaoke/Suggestions/RecommendationProvider.swift`. The engine **never throws** — a total failure yields an empty list (FR-025d)
- [ ] T092 [P] [US2] Add session co-occurrence recording to `Karaoke/Karaoke/Store/Models/SessionLog.swift` so songs sung in the same past session can be related later — this captures the group's actual taste, which no content-based signal provides
- [ ] T093 [P] [US2] Implement the local strategies in `Karaoke/Karaoke/Suggestions/LocalStrategies.swift`: `coOccurrence` from the session log, `history` by play count and recency, and `favourite` for unplayed favourites. These are the backbone and must never fail or require a network
- [ ] T094 [US2] Implement `SameChannelStrategy` in `Karaoke/Karaoke/Suggestions/SameChannelStrategy.swift` using the channel's **uploads playlist**, not the search endpoint — the platform recommends it and it avoids spending the scarce search quota
- [x] ~~T095 [US2] Implement `UpstreamRelatedStrategy`~~ — **CANCELLED by Spike S8 (T015).** YouTubeKit exposes no watch-next data at all, so this would require hand-parsing the InnerTube response: the same undocumented surface that churns ~12 commits per 90 days upstream, costing a rebuild and a re-sign each time, to sit above four strategies that never break. The engine ships with `sameChannel`, `coOccurrence`, `history`, and `favourite`
- [ ] T096 [US2] Implement `RecommendationEngine` in `Karaoke/Karaoke/Suggestions/RecommendationEngine.swift`: gather from every available strategy concurrently under a short overall deadline, deduplicate by `songID` keeping the highest-priority attribution, apply exclusions, rank by strategy priority then `score`, truncate. A strategy missing the deadline contributes nothing and is not awaited
- [ ] T097 [US2] Implement the four exclusion rules in `Karaoke/Karaoke/Suggestions/RecommendationEngine.swift`: the currently playing song; every song in `performedSongIDs` (FR-025c); songs already queued as `waiting`; songs whose last resolution failed with a content-side error this session
- [ ] T098 [US2] Implement `Suggestion` validation in `Karaoke/Karaoke/Suggestions/RecommendationEngine.swift`: `score` in 0…1, `reason` non-empty (a suggestion the singer cannot interpret is noise), and no duplicate `songID` in the result list
- [ ] T099 [US2] Build the suggestions view in `Karaoke/Karaoke/Features/Player/SuggestionsView.swift` showing title, channel, duration, and the singer-facing reason per suggestion (FR-025a, FR-025f), with add-to-queue and play-now actions matching search result behaviour (FR-025e)
- [ ] T100 [US2] Implement the explicit cold-start empty state in `Karaoke/Karaoke/Features/Player/SuggestionsView.swift` distinguishable from a loading state — with no history and no upstream data the app says so plainly rather than rendering an empty list that looks like it is still loading
- [ ] T101 [US2] Regenerate suggestions whenever the current song changes in `Karaoke/Karaoke/Features/Player/PlayerViewModel.swift` and never cache across songs — the exclusion set changes every few minutes, so a cached list is a stale list

### Tests for User Story 2

- [ ] T102 [P] [US2] Write exclusion tests in `Karaoke/KaraokeTests/Suggestions/ExclusionTests.swift` covering all four rules, with the already-sung case tested explicitly because offering the song that just finished is the failure everyone notices immediately
- [ ] T103 [P] [US2] Write deduplication and attribution tests in `Karaoke/KaraokeTests/Suggestions/BlendingTests.swift` asserting a song produced by three strategies appears once, attributed to the highest-priority one
- [ ] T104 [P] [US2] Write ranking determinism tests in `Karaoke/KaraokeTests/Suggestions/RankingTests.swift` asserting ordering follows strategy priority then score, deterministically for a fixed input
- [ ] T105 [P] [US2] Write engine-never-throws tests in `Karaoke/KaraokeTests/Suggestions/EngineResilienceTests.swift` asserting that with every strategy failing the engine returns an empty list rather than propagating an error
- [ ] T106 [P] [US2] Write deadline tests in `Karaoke/KaraokeTests/Suggestions/DeadlineTests.swift` asserting a slow strategy is excluded and does not extend total time
- [ ] T107 [P] [US2] Write local-only guarantee tests in `Karaoke/KaraokeTests/Suggestions/LocalOnlyTests.swift` asserting that with upstream strategies disabled and a populated store the result is still non-empty
- [ ] T108 [P] [US2] Write cold-start tests in `Karaoke/KaraokeTests/Suggestions/ColdStartTests.swift` asserting an empty store with no upstream yields an empty list and the explicit no-suggestions state

### Device validation for User Story 2

- [ ] T109 [US2] Run quickstart.md Scenario 6 including the network capture across twenty songs confirming **zero** search-endpoint calls from the suggestion feature (SC-014)

**Checkpoint**: The party keeps moving on its own.

---

## Phase 7: User Story 4 - Build and run a session (Priority: P3)

**Goal**: Queue songs ahead, advance automatically, and keep favourites across restarts.

**Independent Test**: Add several songs to a queue, confirm order and automatic advance, reorder and remove entries while playing, and confirm favourites survive an app restart.

- [ ] T110 [P] [US4] Implement `QueueService` in `Karaoke/Karaoke/Features/Queue/QueueService.swift` enforcing at most one `current` entry at any time and renumbering `position` to stay contiguous after every insert, remove, or reorder — a gap or duplicate is a defect
- [ ] T111 [US4] Implement queue advance in `Karaoke/Karaoke/Features/Queue/QueueService.swift`: on natural finish the current entry becomes `played` and the lowest-positioned `waiting` entry becomes `current` (FR-026); if none remains, playback stops and the session ends cleanly
- [ ] T112 [US4] Implement failure-tolerant advance in `Karaoke/Karaoke/Features/Queue/QueueService.swift` so an entry whose resolution fails becomes `failed` and the queue advances — one dead song must not stall the party
- [ ] T113 [US4] Implement non-disruptive mutation in `Karaoke/Karaoke/Features/Queue/QueueService.swift` so reordering or removing a non-current entry does not disturb playback, and removing the `current` entry advances exactly as a natural finish would
- [ ] T114 [US4] Implement queue persistence and launch restore in `Karaoke/Karaoke/Features/Queue/QueueService.swift` with `current` restored as `waiting` — the app does not auto-resume audio on cold start
- [ ] T115 [P] [US4] Implement favourites add/remove in `Karaoke/Karaoke/Features/Library/FavouritesService.swift`, pinning the Song against unreferenced cleanup
- [ ] T116 [P] [US4] Build the queue view in `Karaoke/Karaoke/Features/Queue/QueueView.swift` with drag-to-reorder and swipe-to-remove
- [ ] T117 [P] [US4] Build the library view in `Karaoke/Karaoke/Features/Library/LibraryView.swift` listing favourites newest first
- [ ] T118 [P] [US4] Write queue state transition tests in `Karaoke/KaraokeTests/Store/QueueServiceTests.swift` covering position contiguity, single-current invariant, natural advance, failed-entry advance, current-removal advance, and launch restore

**Checkpoint**: Sessions run themselves.

---

## Phase 8: User Story 5 - Sing without the network (Priority: P3)

**Goal**: Save songs ahead of time so a venue with poor connectivity still works.

**Independent Test**: Save three songs, enable airplane mode, confirm each plays at the same quality as online within 1 s, and confirm an unsaved song produces a clear message within 3 s rather than a hang.

- [ ] T119 [US5] Implement the staged-write download in `Karaoke/Karaoke/Store/MediaStore.swift` writing to a staging location and moving into place **atomically** on completion — this is what makes FR-033's promise true, because a failed save never touches an existing one
- [ ] T120 [US5] Implement the `SavedSong` state machine in `Karaoke/Karaoke/Store/SaveCoordinator.swift`: `pending → downloading → complete`, with `failed` on no-space or network error, cancellation deleting the partial file, retry returning to `pending`, and delete removing file and record together
- [ ] T121 [US5] Implement completion verification in `Karaoke/Karaoke/Store/SaveCoordinator.swift` so `complete` is reachable only after the written byte count is verified against the expected size **and** the file is confirmed decodable — a truncated file must never be marked complete
- [ ] T122 [US5] Implement no-space handling in `Karaoke/Karaoke/Store/SaveCoordinator.swift` leaving `state = failed` with an actionable `lastError` and every other SavedSong untouched (FR-033)
- [ ] T123 [US5] Implement storage accounting in `Karaoke/Karaoke/Store/MediaStore.swift` reporting total as the sum of `byteSize` over `complete` entries, with staging bytes reported **separately** so the singer understands a cancel will reclaim them (FR-031)
- [ ] T124 [US5] Implement offline playback routing in `Karaoke/Karaoke/Features/Player/PlaybackSession.swift` preferring `.local(URL)` for saved songs, starting within 1 s (SC-006)
- [ ] T125 [US5] Implement the offline-unavailable message in `Karaoke/Karaoke/Features/Player/PlaybackErrorView.swift` failing clearly within 3 s rather than hanging when an unsaved song is requested with no network (FR-032)
- [ ] T126 [P] [US5] Build the saved-songs management view in `Karaoke/Karaoke/Features/Library/SavedSongsView.swift` with per-song size, download progress, and individual removal
- [ ] T127 [P] [US5] Write save state machine tests in `Karaoke/KaraokeTests/Store/SaveCoordinatorTests.swift` covering every transition, truncated-file rejection, cancellation cleanup, and the no-space case leaving other saves intact
- [ ] T128 [P] [US5] Write storage accounting tests in `Karaoke/KaraokeTests/Store/StorageAccountingTests.swift` asserting the reported total matches the measured media directory minus staging (data-model invariant 6)

**Checkpoint**: The app works at a venue with no signal.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T129 [P] Implement background audio continuity and the now-playing surface in `Karaoke/Karaoke/Audio/NowPlayingController.swift`, wiring transport controls to play, pause, seek, and next-track (FR-015)
- [ ] T130 [P] Implement interruption handling in `Karaoke/Karaoke/Audio/PlayerPipeline.swift`: pause and retain position on interruption, and on interruption end **offer** resumption rather than auto-resuming — a call ending should not blast music at the room mid-conversation (FR-016)
- [ ] T131 [P] Implement speaker-reconnect resumption in `Karaoke/Karaoke/Audio/PlayerPipeline.swift` offering to resume from the paused position rather than restarting the song
- [ ] T132 [P] Implement the signing-validity display in `Karaoke/Karaoke/Features/Settings/SigningValidityView.swift` showing remaining validity and how to restore it, so expiry is a scheduled chore rather than a mystery failure in front of guests (FR-036)
- [ ] T133 [P] Implement the companion service in `Tools/companion-service/` exposing resolve-renditions and resolve-address over HTTP with the same shapes as `SourceProvider`, plus `Tools/companion-service/run.sh`
- [ ] T134 Implement `CompanionSourceProvider` in `Karaoke/Karaoke/Sources/CompanionSourceProvider.swift` and register it in the router chain. **This is not optional** — on-device resolution breaking is a scheduled event, and a server-side fix avoids the rebuild-and-re-sign the singer must perform by hand
- [ ] T135 [P] Add the companion service address setting in `Karaoke/Karaoke/Features/Settings/SettingsView.swift` with a provider-preference control so the singer can promote the companion when on-device breaks
- [ ] T136 [P] Build the 50-song reference list fixture at `Karaoke/KaraokeTests/Fixtures/reference-songs.json` for the SC-005 daily resolution check — it only means something if the list stays fixed
- [ ] T137 [P] Implement bounded resolution for very long sources in `Karaoke/Karaoke/Sources/OnDeviceSourceProvider.swift` so a multi-hour compilation does not load wholly into memory
- [ ] T138 [P] Add explicit timeouts to every network call in `Karaoke/Karaoke/Sources/` surfacing as `timeout(stage:)` which names where it hung
- [ ] T139 [P] Implement task cancellation handling across every async method in `Karaoke/Karaoke/Sources/` so an abandoned search leaves no work running
- [ ] T140 Run quickstart.md Scenario 7 (interruptions and the Bluetooth link) including power-off, reconnect, and walk-out-of-range (SC-010)
- [ ] T141 Run quickstart.md Scenario 8 (honest failure) against the 50-song reference list, recording classification correctness for every failure (SC-005)
- [ ] T142 Run quickstart.md Scenario 9 (fallback) proving the companion provider actually serves requests — an untested fallback is not a fallback
- [ ] T143 Run quickstart.md Scenario 10 (offline) including the cancelled-save case that must leave existing saves intact (SC-011)
- [ ] T144 Run quickstart.md Scenario 11 (a real party): two hours, 15+ songs, network capture confirming no unexpected destination, then ten restarts (SC-002, SC-009, SC-012, SC-013)
- [ ] T145 Run quickstart.md Scenario 12 (suggestion quality) at a real party, recording acceptance by strategy, and tune the blend ordering from the result

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Measurement Spikes (Phase 2)**: Depends on Setup. T009 and T010 need the physical speaker. **Blocks everything** — research.md forbids citing a **[prior]** finding before its spike runs
- **Foundational (Phase 3)**: Depends on Phase 2. T031 needs T012's codec finding. **Blocks all user stories**
- **User Stories (Phases 4–8)**: All depend on Phase 3
- **Polish (Phase 9)**: Depends on the desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Needs Phase 3 only. No dependency on other stories. **This is the MVP**
- **US3 (P2, words)**: Needs Phase 3 and US1's `PlayerPipeline` for position and `OutputRouteMonitor` for delay. Sequenced **before** US2 per plan.md because the delay compensation is the harder problem
- **US2 (P2, suggestions)**: Needs Phase 3 and US1's `PlaybackSession` for `performedSongIDs`. Independent of US3
- **US4 (P3, queue)**: Needs Phase 3 and US1. Independent of US2 and US3
- **US5 (P3, offline)**: Needs Phase 3 and US1. Independent of US2, US3, US4

### Within Each User Story

- Protocol definitions before implementations
- Models before services, services before views
- Tests may be written before or alongside implementation, but must be observed to fail before the fix (Constitution Quality Gate 3)
- Device validation last, and it is the only evidence that counts for audio, timing, and route behaviour

### Parallel Opportunities

- Setup: T005–T008 in parallel
- Spikes: T014 and T015 run in parallel with each other; T009–T013 need the device or network sequentially
- Foundational models: T016–T022 all in parallel
- Foundational protocol definitions: T026, T027, T028 in parallel
- Foundational tests: T036–T043 all in parallel
- Within US1: T044 and T045 in parallel; tests T062–T067 all in parallel
- Within US3: tests T083–T088 all in parallel
- Within US2: T091, T092, T093 in parallel; tests T102–T108 all in parallel
- Across stories: once Phase 3 completes, US2, US4, and US5 can proceed in parallel with US3

---

## Parallel Example: Foundational Models

```bash
# All seven model files are independent — launch together:
Task: "Create the Song SwiftData model in Karaoke/Karaoke/Store/Models/Song.swift"
Task: "Create the SavedSong SwiftData model in Karaoke/Karaoke/Store/Models/SavedSong.swift"
Task: "Create the Favourite SwiftData model in Karaoke/Karaoke/Store/Models/Favourite.swift"
Task: "Create the QueueEntry SwiftData model in Karaoke/Karaoke/Store/Models/QueueEntry.swift"
Task: "Create the PerformanceSettings singleton in Karaoke/Karaoke/Store/Models/PerformanceSettings.swift"
Task: "Create LyricsTrack/Line/Word models in Karaoke/Karaoke/Store/Models/LyricsTrack.swift"
```

## Parallel Example: User Story 1 Tests

```bash
# Six independent test files:
Task: "Session-category test in Karaoke/KaraokeTests/Audio/AudioSessionControllerTests.swift"
Task: "Volume clamping tests in Karaoke/KaraokeTests/Audio/VolumeTests.swift"
Task: "Route classification tests in Karaoke/KaraokeTests/Audio/OutputRouteTests.swift"
Task: "External-output-lost tests in Karaoke/KaraokeTests/Audio/OutputLossTests.swift"
Task: "Stall-handling tests in Karaoke/KaraokeTests/Audio/StallTests.swift"
Task: "Seek bounds tests in Karaoke/KaraokeTests/Audio/SeekTests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup — T001–T008
2. Phase 2: Spikes — T009–T015, **with the real speaker**
3. Phase 3: Foundational — T016–T043
4. Phase 4: User Story 1 — T044–T071
5. **STOP and VALIDATE**: quickstart.md Scenarios 1–4 on a physical device
6. Sing with it

At this point the app searches YouTube, plays ad-free through the PA speaker at the best decodable rendition, and never touches the microphone. That is a usable karaoke machine.

### Incremental Delivery

1. Setup + Spikes + Foundational → foundation ready
2. US1 → validate → **MVP, start using it**
3. US3 (words) → validate Scenario 5 → the hardest criterion is met
4. US2 (suggestions) → validate Scenario 6 → the party runs itself
5. US4 (queue) → validate → sessions manage themselves
6. US5 (offline) → validate Scenario 10 → works anywhere
7. Polish → T134 is the one that matters most: the companion fallback

### Solo Developer Ordering

This is a one-person project (Constitution Principle VII), so the parallel-team strategy does not apply. The useful sequencing is:

- Do the spikes **before** writing code that depends on them. T009 and T010 together take an evening and prevent rebuilding the lyrics layer
- Build T037 (error classification) early even though it feels like overhead — it is the test that catches resolution breakage before the library looks empty
- Do not defer T134 (companion provider). It is the difference between a breakage costing a minute and costing an evening

---

## Notes

- [P] = different files, no dependencies on incomplete tasks
- Every task names an exact file path
- Device validation tasks are **not** optional and **not** replaceable by simulator runs (Principle III)
- No real song text is committed anywhere — lyrics fixtures use synthetic placeholders only
- T095 may legitimately be skipped if T015 concludes the upstream strategy is not worth its churn
- Commit after each task or logical group
