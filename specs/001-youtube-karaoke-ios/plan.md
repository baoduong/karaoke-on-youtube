# Implementation Plan: YouTube-Sourced Karaoke App for iPhone/iPad

**Branch**: `001-youtube-karaoke-ios` | **Date**: 2026-11-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-youtube-karaoke-ios/spec.md`

## Summary

A personal, sideloaded iPhone/iPad application that searches YouTube for karaoke backing tracks, resolves each to the highest-quality audio rendition the device can actually decode, and plays it ad-free through a portable PA speaker, with the words on screen and singer controls for key, tempo, and volume.

A personal, sideloaded iPhone/iPad application that searches YouTube for karaoke backing tracks, plays them ad-free over Bluetooth to a portable PA speaker with the words on screen, and suggests what to sing next.

Four decisions, all confirmed with the user, shape everything:

**Playback only.** The PA speaker ("loa kéo") owns the microphone, its preamp, its vocal effects, and the vocal-versus-music mix, all in hardware. The app captures no audio.

**No pitch or tempo processing.** Songs play as published. The app picks the best rendition rather than trying to improve a lesser one.

**Bluetooth is the only output route.** Accepted knowingly, with two consequences documented rather than discovered: the link re-encodes the audio, and it delays it enough to desynchronise the words unless compensated.

**Personal sideload.** Sourcing media outside the official player conflicts with App Store policy, so the App Store is out of scope.

Together the first two collapse the audio layer to almost nothing. With no capture path and nothing to process, there is no reason to own an audio processing graph — the system's standard media player already streams, decodes, buffers, plays in the background, and reports position. **The app has no render thread and no real-time code.**

That leaves two things genuinely worth engineering care, and the plan is shaped around them:

1. **Source resolution, which will break.** yt-dlp's YouTube extractor took 12 commits in 90 days. On-device breakage is a scheduled event, so a companion fallback exists that is fixed server-side without a rebuild and re-sign.
2. **Word timing over Bluetooth.** The player reports what it dispatched; the speaker emits it a sixth of a second later. Because Bluetooth is the only route, an implementation that omits the compensation is wrong for every song.

The suggestion feature turned out to need its own design rather than an API call: the platform's related-videos parameter no longer exists, and the search allowance is 100 calls per day. Suggestions are therefore built mostly from local history, with upstream data as an optional extra.

## Technical Context

**Language/Version**: Swift 6, strict concurrency enabled.

**Primary Dependencies**:
- [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) — MIT, actively maintained (0.4.10, 2026-10-25) — on-device source resolution.
- YouTube Data API v3 — search and metadata only; it exposes no stream addresses.
- [LRCLIB](https://lrclib.net) — optional, opt-in, no authentication — synchronized words.
- Platform frameworks only otherwise: the standard media player for playback, the now-playing/remote-command surface for background control, SwiftUI for the interface. **No audio engine** — nothing is left to process.

Deliberately absent: no networking library, no dependency-injection framework, no architecture framework, no analytics, no crash reporter. Principle VII — every abstraction pays for itself, and nothing phones home.

**Storage**: SwiftData for metadata; plain files in the app's own container for saved audio. Audio bytes stay out of the database so a save can be staged and moved into place atomically, which is what makes FR-033 ("a failed save cannot corrupt an existing one") true rather than aspirational.

**Testing**: Swift Testing for logic that rots silently — rendition ranking, error classification, lyric timing and seek correction, queue transitions, cache accounting, settings clamping, and every parser handling upstream data. Fixtures are recorded payloads; the suite never touches the live network. Device measurement, not unit tests, covers audio behaviour, route delay, and sustained-session stability (Principle III: simulator results do not count).

**Target Platform**: iOS/iPadOS 17.0+. Chosen for SwiftData and modern Swift concurrency; the app is personal and the singer controls their own devices, so there is no legacy-OS constituency to serve.

**Project Type**: Mobile application, single target, no server component the project operates. The optional companion resolution service is software the singer runs on their own hardware and is specified here but not operated by this project.

**Performance Goals**:
- Playback begins within 5 s of selection on a typical home connection; within 1 s for a saved song (SC-006).
- Volume changes audible within 200 ms with no click; output otherwise bit-identical to the decoded source (SC-007).
- Words within 150 ms of the sound the room hears over Bluetooth, including after seeks (SC-008).
- Suggestions within 3 s of a song starting, for at least 90% of songs, never blocking playback (SC-014).
- Two hours continuous with no crash, no dropout, bounded memory (SC-009).

**Constraints**:
- Zero advertising anywhere in the singer's path (FR-006, SC-002).
- Zero microphone access — no capture, no permission prompt, no privacy string (FR-010, SC-003).
- Zero audio processing — output is the decoded source with level applied and nothing else (FR-011, SC-007).
- Zero outbound traffic to any service this project operates (FR-035, SC-012); the only destinations are the upstream source and, if the singer opts in, the lyrics service.
- No account, no sign-in (FR-034).
- **The Bluetooth link, not the upstream rendition, sets the audio quality ceiling.** It re-encodes already-lossy audio. The app reports this honestly (FR-014) rather than advertising a bitrate the link discards.
- **Search is capped at 100 calls per day.** Search is submit-driven, cached per session, and suggestions may not spend any of it.
- Source resolution will break periodically. Accepted and designed for, not engineered away.

**Scale/Scope**: One household. A few hundred songs in the local store at most. Roughly 8–12 screens. Four protocol boundaries, three of which have more than one implementation.

**No unresolved NEEDS CLARIFICATION.** Seven questions carry named spikes with defined outcomes in [research.md](./research.md). **S5** — route delay compensation over the actual speaker — runs first: on a Bluetooth-only design, omitting it is wrong for every song, and it is the measurement behind the project's hardest success criterion.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against [`.specify/memory/constitution.md`](../../.specify/memory/constitution.md) v1.0.0.

### Initial evaluation (pre-Phase 0)

| Principle | Verdict | Basis |
|---|---|---|
| I — The Audio Path Is Sacred | **NOT APPLICABLE** | See note below. No render thread exists in this design. |
| II — The Upstream Will Break | **PASS** | All upstream interaction behind `SourceProvider`; two implementations from the start. |
| III — Verify the Claim | **PASS** | Every success criterion is measurable; device measurement required for audio, timing, and network. |
| IV — Test What Can Silently Rot | **PASS** | Test scope named per contract; UI layout explicitly excluded. |
| V — Nothing Leaves the Device | **PASS** | No server, no account, no analytics. Lyrics opt-in and off by default. Suggestions computed locally. |
| VI — Honest Failure | **PASS** | Error taxonomy separates content-side from mechanism-side failure. Route-induced quality loss disclosed rather than hidden. |
| VII — One Developer's Scale | **PASS WITH NOTE** | Four protocol boundaries in a solo project needs justification. Given below. |

**Principle I is unreachable, not violated.** It was written for a design that owned a render thread, and its forbidden-operations list governs code inside render callbacks. Removing pitch and tempo processing removed the last reason to own an audio graph, so no such callback exists anywhere in this design. The principle is recorded as not applicable rather than amended away — reintroducing any audio processing brings it back in full, and the note in [audio-pipeline.md](./contracts/audio-pipeline.md) says so.

**Principle VII justification.** The constitution permits an abstraction only where a second implementation or a real-time-safety reason exists. All four boundaries clear that bar; none is speculative:

- `SourceProvider` — two real implementations, mandated by Principle II, justified by the measured 12-commits-in-90-days churn in the reference extractor.
- `AudioPipeline` — kept despite Principle I no longer applying, because it is the seam that keeps the playback-only and no-processing guarantees testable. Its session-category test is what keeps FR-010 true as the code changes.
- `LyricsProvider` — "no provider configured" is a first-class, common state, because most karaoke sources already show the words. The protocol is what makes absence normal instead of exceptional.
- `RecommendationProvider` — five concrete strategies behind it, four of which are local and one of which may never be built (Spike S8). A blended engine with a shifting set of contributors is exactly the case a protocol is for.

No fifth boundary. Views talk to a view model; view models talk to these four protocols and the store. There is no repository layer, no use-case layer, no coordinator.

### Post-design re-evaluation (after Phase 1)

| Principle | Verdict | What the design actually produced |
|---|---|---|
| I | **N/A** | No render thread, no processing graph, no real-time code. Recorded in the audio contract with the condition under which it reapplies. |
| II | **PASS** | `SourceProvider` plus a router that falls through on mechanism-side errors but *not* on content-side ones. The error taxonomy separates the two, and the classification test is named as the highest-value test in the project. |
| III | **PASS** | research.md tags each finding **[verified]** or **[prior]**, and no **[prior]** may be cited as evidence until its spike runs. Seven spikes, reordered by the latest scope changes, with two retired and one resolved outright by a verified fact. |
| IV | **PASS** | Each contract carries a test section split into automated (logic that rots) and device-only. The recommendation contract explicitly declines to unit-test suggestion *quality*, which no test can judge — exactly the kind of test the constitution rejects. |
| V | **PASS** | Data-model invariant 7 states it; SC-012 verifies it by network capture. Suggestions are computed from local data and nothing about the singer's taste is transmitted. Stream addresses are forbidden from logs, errors, and storage (invariant 4). |
| VI | **PASS** | `SourceError` separates content-side, mechanism-side, and environment failures. Beyond that, the design discloses an uncomfortable truth rather than hiding it: `degradesQuality` tells the singer the Bluetooth link is throwing away the quality the app worked to obtain. |
| VII | **PASS** | Four boundaries, each justified. Two scope changes removed two subsystems — capture, then processing — and added one small local engine. The design got smaller overall. |

**No violations. Complexity Tracking table is empty and omitted.**

Two observations worth recording:

**The scope changes improved the constitution position rather than merely narrowing it.** Removing capture removed the sharpest Principle I hazard. Removing pitch and tempo removed Principle I's subject matter entirely, along with the audio graph, the buffering concerns, and two planned spikes. Each round of "we don't need that" left a design with fewer ways to be wrong.

**The suggestion feature reversed its own obvious design under evidence.** It began as "call the related-videos API", became "that API no longer exists", then "search costs too much to spend on it", and ended as a mostly-local engine that is more private, never breaks, works offline, and uses a signal — which songs this group sings together — that no upstream API could provide. Worth noting because the final design is better than the one originally asked for, and it got there by checking rather than assuming.

## Project Structure

### Documentation (this feature)

```text
specs/001-youtube-karaoke-ios/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — decisions, evidence tags, 7 spikes
├── data-model.md        # Phase 1 output — 10 entities, state machines, invariants
├── quickstart.md        # Phase 1 output — build, install, and validation guide
├── contracts/           # Phase 1 output
│   ├── source-provider.md
│   ├── audio-pipeline.md
│   ├── lyrics-provider.md
│   └── recommendation-provider.md
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
Karaoke/
├── Karaoke.xcodeproj
├── Karaoke/
│   ├── KaraokeApp.swift
│   ├── Info.plist                       # background audio; NO microphone usage string
│   │
│   ├── Sources/                         # SourceProvider boundary — Principle II
│   │   ├── SourceProvider.swift         # protocol, SourceError, ResolutionStage
│   │   ├── SourceProviderRouter.swift   # ordered fallback, health checks, attribution
│   │   ├── OnDeviceSourceProvider.swift # YouTubeKit — the part that will break
│   │   ├── CompanionSourceProvider.swift# self-hosted yt-dlp service on the LAN
│   │   ├── DataAPISearchProvider.swift  # YouTube Data API v3 — search/metadata only
│   │   └── RenditionSelection.swift     # pure ranking function — SC-004 verifiable
│   │
│   ├── Audio/                           # AudioPipeline boundary
│   │   ├── AudioPipeline.swift          # protocol, events, errors
│   │   ├── PlayerPipeline.swift         # system media player; no processing graph
│   │   ├── AudioSessionController.swift # playback-only category; never record
│   │   └── OutputRouteMonitor.swift     # route kind, latency, degradesQuality
│   │
│   ├── Lyrics/                          # LyricsProvider boundary
│   │   ├── LyricsProvider.swift         # protocol, LyricsError
│   │   ├── LRCLIBProvider.swift
│   │   ├── LyricsParser.swift           # parse + the 5 rejection rules
│   │   └── LyricsTimeline.swift         # pure lookup; subtracts route delay
│   │
│   ├── Suggestions/                     # RecommendationProvider boundary
│   │   ├── RecommendationProvider.swift # protocol, strategies, errors
│   │   ├── RecommendationEngine.swift   # blend, exclude, rank; never throws
│   │   ├── UpstreamRelatedStrategy.swift# optional; may not be built (S8)
│   │   ├── SameChannelStrategy.swift    # uploads playlist, never search
│   │   └── LocalStrategies.swift        # co-occurrence, history, favourites
│   │
│   ├── Store/
│   │   ├── Models/                      # SwiftData models per data-model.md
│   │   ├── MediaStore.swift             # staged write, atomic move, reconciliation
│   │   └── StoreReconciler.swift        # launch-time invariant repair
│   │
│   ├── Features/
│   │   ├── Search/
│   │   ├── Player/                      # transport, key/tempo/volume, route status
│   │   ├── Lyrics/                      # large-type display, read-ahead
│   │   ├── Queue/
│   │   ├── Library/                     # favourites, saved songs, storage usage
│   │   └── Settings/                    # lyrics opt-in, offset trim, signing validity
│   │
│   └── Common/
│
├── KaraokeTests/
│   ├── Sources/                         # ranking, error classification, routing
│   ├── Audio/                           # session category, clamping, route classification
│   ├── Lyrics/                          # parsing, rejection rules, lookup, seek, delay
│   ├── Suggestions/                     # exclusions, dedup, ranking, never-throws
│   ├── Store/                           # save state machine, reconciliation, accounting
│   └── Fixtures/                        # recorded payloads; synthetic placeholder text only
│
└── Tools/
    └── companion-service/               # optional, runs on the singer's own machine
```

**Structure Decision**: A single iOS application target with internal module directories, rather than separate Swift packages. The three protocol boundaries are enforced by discipline and review, not by package visibility — under Principle VII, package-splitting a solo project of this size buys build-time friction and no safety the boundaries do not already provide. `Tools/companion-service/` is deliberately outside the app target: it is software the singer runs on their own machine, specified here so the fallback is real, not operated by this project.

The directory layout mirrors the contracts one-to-one so that when resolution breaks — and research.md establishes that it will, roughly weekly in the reference implementation — the change is confined to `Sources/` and the blast radius is obvious before the first line is edited.

## Implementation Sequencing

Not a task list — that is `/speckit.tasks`. This is the dependency order those tasks must respect, because getting it wrong wastes the most expensive work.

1. **Spikes S5 and S0 first, with the real speaker.** Measure route delay and the link's codec before building anything that depends on either. S5 is the project's most important measurement: Bluetooth is the only route, so a missing compensation is wrong for every song. S0 tells the app how honest to be about quality and whether S1 is worth effort at all.
2. **Spike S7.** Background audio, LAN reachability, and signature validity on a physical device. Cheap now, expensive to discover late — particularly LAN access, which the companion provider depends on entirely.
3. **The resolution layer**, with the error taxonomy and its classification test. That test is the project's highest-value test because the failure it catches — a broken parser reported as "song unavailable" — hides breakage until the whole library looks empty.
4. **Playback.** Small, because the system player does the work. Spike S1 fits here, now that S0 has sized how much it matters.
5. **User Story 1 end to end.** Search, select, play, ad-free. At this point the app is useful and everything after is enhancement.
6. **User Story 3 — words** — including the route-delay compensation that S5 measured. S6 resolves the lyrics lookup path.
7. **User Story 2 — suggestions.** Build the local strategies first; they carry the feature. Run S8 to decide whether the upstream strategy is worth writing at all, and be willing to skip it.
8. **User Stories 4 and 5** — queue and offline. The save state machine's atomic-move behaviour is the part worth care; the rest is ordinary.

Note the reordering: words now precede suggestions, because the delay compensation is the harder problem and the one the Bluetooth decision made unavoidable.

## Risks

| Risk | Likelihood | Impact | Response |
|---|---|---|---|
| On-device resolution breaks | **Certain**, recurring | App unusable until rebuilt *and re-signed* | `CompanionSourceProvider` fixes server-side with no re-sign. The single strongest reason the fallback is not optional. |
| Words drift behind the Bluetooth speaker | **Certain if uncompensated** | SC-008 fails on every song | Route delay subtracted at lookup (FR-019) plus a manual trim (FR-020). S5 measures it first. |
| Bluetooth re-encode caps audio quality | **Certain** | The headline requirement is partly unmet | Accepted by the user. Disclosed via `degradesQuality` (FR-014) rather than hidden. A cable remains the known-better option. |
| Search allowance of 100/day exhausted | Possible | Search stops working mid-party | Submit-driven, cached per session; suggestions forbidden from spending it. Provider-native search as fallback. |
| Upstream relation data unobtainable | **Likely** | `upstreamRelated` never ships | Four local strategies carry the feature. S8 may legitimately conclude "don't build it". |
| Suggestions feel stale or repetitive | Possible | Feature ignored | Session-exclusion is mandatory; co-occurrence gives taste-specific signal. Judged at a real party, not by a test. |
| Signature expires mid-party | Likely on a free account | App refuses to launch in front of guests | Paid account recommended; remaining validity surfaced in-app (FR-036). |
| Lyrics coverage thin, especially Vietnamese | Likely | Word display often unavailable | FR-022 is a SHOULD. The video image carries the words for most sources; no-provider is a normal state. |
| Highest-bitrate renditions undecodable | Likely | Small real quality loss | S1 answers it; the Bluetooth re-encode masks most of the difference anyway. |

## Complexity Tracking

No Constitution Check violations. Table omitted.
