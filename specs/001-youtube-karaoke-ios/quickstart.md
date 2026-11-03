# Quickstart & Validation Guide

**Feature**: `001-youtube-karaoke-ios` | **Phase**: 1 (Design)

How to build, install, and prove this app works. Every scenario here maps to a success criterion in [spec.md](./spec.md) and produces a pass or fail, not an impression.

**The governing rule** (Constitution Principle III): the simulator does not count for anything involving audio, output routes, network timing, or background behaviour. Every scenario below runs on a physical iPhone or iPad with the real PA speaker attached. A green simulator run is not evidence.

---

## Prerequisites

### Hardware

| Item | Why it is required |
|---|---|
| iPhone or iPad, iOS/iPadOS 17.0+ | Deployment target |
| Mac with Xcode 16+ | Build and signing |
| The actual PA speaker ("loa kéo"), paired over Bluetooth | The only supported route, and the output device under test. Headphones will not reveal the route-delay failures |
| A cable to the same speaker | Not a supported route — used once, as a calibration reference, to separate link delay from code error |
| A second device that can record video | Needed to measure display-versus-audio alignment (SC-008) |

### Accounts and keys

- An Apple Developer account. The paid program is recommended — see [research.md](./research.md) R6 for why a short signing window is a product defect rather than an inconvenience.
- Optionally, a YouTube Data API v3 key for search. Without one the app falls back to provider-native search.
- No account is needed for lyrics. LRCLIB requires no authentication ([research.md](./research.md) R5, verified).

### Reference material you must prepare

- **A 50-song reference list** of karaoke sources, saved as a fixture. SC-005 measures daily resolution success against this list, and it only means something if the list is fixed. Build it once, do not edit it casually.
- **A test song with a sharp transient** near the start — a count-in click, a drum hit. The alignment measurement in Scenario 6 depends on having a moment you can see and hear precisely.
- **A long source**, over an hour, for the bounded-resolution edge case.

---

## Build and install

```bash
git clone <repository> && cd karaoke-on-youtube
open Karaoke/Karaoke.xcodeproj
```

In Xcode: select your team under Signing & Capabilities, confirm **Background Modes → Audio** is enabled, select your physical device, and run.

**Confirm before going further** that `Info.plist` contains **no** microphone usage description. Its absence is the enforcement mechanism for FR-010 — the app cannot request what it has no string for, and Scenario 2 verifies the consequence.

```bash
xcodebuild -scheme Karaoke -destination 'generic/platform=iOS' build   # must produce no new warnings
xcodebuild -scheme Karaoke -destination 'platform=iOS,name=<device>' test
```

### Optional: the companion resolution service

Only needed when on-device resolution breaks — which [research.md](./research.md) R2 establishes is a recurring, scheduled event rather than a hypothetical. Run it on a machine on the same network:

```bash
cd Tools/companion-service && ./run.sh
```

Then point the app at its address in Settings. Scenario 9 proves the fallback actually works, which is the only thing that makes it a fallback rather than an aspiration.

---

## Validation scenarios

Run 1 through 6 for any change touching playback, resolution, or lyrics. Run all eleven before declaring a release — meaning a build you intend to sing with.

### Scenario 1 — Search to sound (SC-001, SC-002, SC-006)

**Covers**: User Story 1, FR-001 … FR-006

1. Pair the PA speaker over Bluetooth. Launch the app cold.
2. Start a stopwatch, search a song by name, select the first plausible karaoke result.
3. Stop the stopwatch when sound is audible from the speaker.

**Pass**: audible within 30 s of launch overall and within 5 s of selection. Results showed title, channel, and duration. **No advertisement appeared at any point.**

**Fail if**: any ad appeared; sound came from the device's own speaker instead of the PA; the result list omitted duration (it is needed for the lyrics duration check).

---

### Scenario 2 — The app never touches the microphone (SC-003)

**Covers**: FR-010

1. Fresh install on a device where the app has never run.
2. Exercise every screen: search, play, controls, queue, library, settings.
3. Open the system's privacy settings and inspect microphone access.

**Pass**: no microphone permission prompt appeared anywhere, and the app does not appear in the microphone access list.

**Fail if**: a prompt appears, or the app is listed. Either means a record-capable audio session was configured somewhere — check `AudioSessionController` against the contract's rule 6.

This scenario is cheap and catches a regression that is otherwise invisible until a user complains about a surprising prompt.

---

### Scenario 3 — Quality selection is honest (SC-004)

**Covers**: FR-004, FR-005

1. Play a song. Open the quality detail the app exposes and record the rendition it chose: format, codec, bitrate.
2. Independently list every audio rendition that source offers.
3. Compare: was the choice the best one the device can actually decode?

**Pass**: the choice is the highest-bitrate decodable rendition, on at least 95% of a 20-song sample.

**Fail if**: the app chose a lower-quality rendition when a better decodable one existed, or it reports a rendition it is not actually playing.

**Note**: what "best decodable" means depends entirely on the outcome of Spike S1. Until S1 has run, this scenario cannot be scored — run S1 first.

---

### Scenario 4 — Volume, and nothing else touches the audio (SC-007)

**Covers**: FR-011, FR-012, FR-013

1. With a track playing, sweep the volume across its range and back.
2. Confirm the app offers **no** key or tempo control anywhere in its interface.
3. Capture the app's output and compare it against the decoded source file.

**Pass**: volume changes audible within about 200 ms with **no click, gap, dropout, or restart**. No pitch or tempo control exists. The captured output is the decoded source with level applied and nothing else — no resampling, no normalisation, no "enhancement".

**Fail if**: any audible discontinuity on a volume change, or the capture shows the audio has been altered. Songs play as published; an app that quietly "improves" the sound is not doing what was asked.

---

### Scenario 5 — Words follow the audio over Bluetooth (SC-008) — the one that matters

**Covers**: User Story 3, FR-019 … FR-024

This is the single most important validation in this guide. Bluetooth is the only supported route, so an implementation that omits route-delay compensation is wrong for **every song** — there is no configuration in which the mistake hides.

1. Speaker paired over Bluetooth. Play the song with the sharp transient.
2. Record video capturing both the screen and the room sound at once.
3. Step through the recording and measure the gap between the highlight advancing and the sound arriving.
4. Seek three times and repeat the measurement after each.
5. For reference only, repeat once over the cable — not because the cable is supported, but to separate how much of any observed gap is the radio link and how much is a code error.

**Pass**: highlight within 150 ms of the sound throughout, including after every seek, with no visible catch-up animation. Upcoming lines are visible so the singer can read ahead. Text legible across a room on iPad.

**Fail if**: the words visibly lead the sound. That is the route delay not being subtracted — check `LyricsTimeline` against rule 4 in [contracts/lyrics-provider.md](./contracts/lyrics-provider.md).

**Also record**: the measured delay versus what the system reported for this speaker. Bluetooth speakers frequently misreport it; the difference is what FR-020's manual trim must cover. Confirm the trim moves the highlight by exactly the amount set.

---

### Scenario 6 — Suggestions (SC-014)

**Covers**: User Story 2, FR-025a … FR-025f

1. Fresh install, no history. Play a song and look at the suggestions. Note what appears.
2. Play five more songs. Check the suggestions again.
3. Confirm no song already sung this session appears in the list.
4. Pick a suggestion and confirm it queues or plays exactly as a search result would.
5. Check that each suggestion states where it came from.
6. Disable the network entirely and confirm suggestions still appear.
7. Watch the app's network traffic across twenty songs and count calls to the search endpoint.

**Pass**: suggestions appear within 3 s for at least 90% of songs. No already-sung song is ever offered. Every suggestion carries a readable reason. Suggestions still appear with no network, drawn from local history. **Zero search-endpoint calls are made by the suggestion feature.**

**Fail if**: the song that just finished is offered as the next one — the visible failure that makes the feature look broken. Also fail if suggestions consume search quota, which would break the search the singer actually needs.

**Note**: cold start on step 1 may legitimately produce nothing. It must say so plainly rather than show an empty list that looks like it is still loading.

**Not scored here**: whether the suggestions are *good*. That is Scenario 12.

---

### Scenario 7 — Interruptions and the Bluetooth link (SC-010)

**Covers**: FR-015 … FR-018

1. Playing: background the app, then lock the screen. Confirm audio continues and the system transport controls work.
2. Trigger an interruption (an incoming call or an alarm). Confirm playback pauses and the position is kept. End it — confirm the app offers resumption and does **not** auto-resume.
3. Power off the PA speaker mid-song.
4. Power it back on and reconnect.
5. Walk to the edge of Bluetooth range until the audio stutters, then walk back.

**Pass**: background and lock-screen playback uninterrupted; transport controls correct; interruption pauses and waits. **Losing the speaker pauses rather than falling through to the device's own speaker.** Reconnection offers to resume from the paused position, not restart the song. A stuttering link recovers on its own.

**Fail if**: audio continues out of the device's tiny speaker after the PA drops — at party volume that is a genuinely unpleasant failure, which is why FR-018 exists. Also fail if a stutter from walking out of range triggers a stream re-resolution; a radio problem is not a stream problem, and re-resolving makes it worse while spending quota.

---

### Scenario 8 — Failures are honest (SC-005)

**Covers**: FR-007, FR-008, and the spec's withdrawn-source edge case

1. Queue a source known to be removed or private. Confirm the message says the song is unavailable and the queue advances rather than stalling.
2. Disable the network mid-song, then re-enable it.
3. Run the 50-song reference list and record successes, failures, and how each failure was classified.
4. Leave a resolved song queued long enough for its address to expire, then play it.

**Pass**: at least 95% of the reference list resolves. Every failure is classified correctly — *this song is unavailable* versus *the mechanism is broken*. The expired-address case re-resolves and plays with no audible gap.

**Fail if**: a parse failure is reported to the singer as "song unavailable". That misclassification hides breakage until the whole library appears empty, and catching it is the single highest-value check in this guide.

---

### Scenario 9 — The fallback is real

**Covers**: [source-provider.md](./contracts/source-provider.md) routing

1. Start the companion service and configure its address.
2. Deliberately disable the on-device provider.
3. Search and play three songs.
4. Re-enable on-device and confirm it is preferred again.

**Pass**: everything works through the companion with no behavioural difference the singer notices; the app reports which provider served each request.

**Fail if**: this has never been run. An untested fallback is not a fallback — and given that on-device resolution is expected to break roughly as often as the reference extractor changes, this is the scenario that determines whether a breakage costs an evening or a minute.

---

### Scenario 10 — Offline (SC-011)

**Covers**: User Story 5, FR-029 … FR-033

1. Save three songs, watching progress to completion.
2. Note the reported storage used.
3. Enable airplane mode. Play each saved song.
4. Attempt an unsaved song.
5. Re-enable the network. Start a save and cancel it mid-way. Confirm the existing saved songs are untouched and the reclaimed space is reported.
6. Delete one saved song and confirm both the file and the record are gone.

**Pass**: saved songs play offline at the same quality as online, starting within 1 s. Unsaved songs produce a clear message within 3 s — **not a hang**. A cancelled save leaves every other save intact.

**Fail if**: a saved song plays at lower quality offline, or a failed save damages an existing one. The staged-write-and-atomic-move behaviour is what prevents the latter.

---

### Scenario 11 — A real party (SC-002, SC-009, SC-012, SC-013)

**Covers**: the whole thing

1. Build a queue of at least 15 songs. Play continuously for two hours through the Bluetooth PA speaker.
2. Reorder and remove entries while playing. Mark favourites.
3. Run a network capture for the whole session.
4. Afterwards: force-quit and relaunch ten times.

**Pass**: no crash, no dropout, no advertisement across the full two hours. Memory and storage stay bounded. **The capture shows no traffic to any destination other than the upstream source and, if enabled, the lyrics service.** Queue, favourites, and settings survive all ten restarts.

**Fail if**: the capture shows any unexpected destination. Principle V is not a preference.

---

### Scenario 12 — Are the suggestions actually any good?

**Covers**: User Story 2, judged rather than measured

The recommendation contract deliberately declines to unit-test suggestion quality, because no test can tell a sensible suggestion from a silly one. This scenario is how that judgement gets made.

1. Use the app for a full evening with real people, letting suggestions drive at least a third of the song choices.
2. For each suggestion accepted or rejected, note which strategy produced it.
3. Afterwards, count acceptance by strategy.

**Pass**: suggestions drove song choices without anyone reaching for search; no suggestion was visibly absurd.

**What to do with the result**: if one strategy is consistently rejected, lower its priority or drop it. If `sameChannel` dominates acceptance, weight it higher. This is the only feedback loop that can tune the blend, and it is worth running every few months rather than once.

---

## Scenario-to-criterion map

| Scenario | Criteria |
|---|---|
| 1 Search to sound | SC-001, SC-002, SC-006 |
| 2 No microphone | SC-003 |
| 3 Quality honesty | SC-004 |
| 4 Volume only, no processing | SC-007 |
| 5 Words over Bluetooth | SC-008 |
| 6 Suggestions | SC-014 |
| 7 Interruptions, link | SC-010 |
| 8 Honest failure | SC-005 |
| 9 Fallback | contract routing |
| 10 Offline | SC-011 |
| 11 Party | SC-002, SC-009, SC-012, SC-013 |
| 12 Suggestion quality | judged, not measured |

Every success criterion is covered. Scenario 5 absorbed what was previously two scenarios: with Bluetooth as the only route, there is no second route to test, and the cable measurement it retains is a calibration reference rather than a pass condition.

---

## Release gate

Before installing a build you intend to sing with, from the constitution's Quality Gates:

- [ ] Builds for a physical device with no new warnings
- [ ] Automated suite green in a single run
- [ ] Scenarios 1 through 11 all pass on real hardware over the real Bluetooth speaker
- [ ] Every claim about audio, delay, network, or routes is backed by a measurement from this guide, not an assumption
- [ ] Scenario 11 completed with no crash, no dropout, no advertisement
- [ ] Remaining signature validity checked, and long enough to cover the occasion

Scenario 12 is not a release gate — it is a periodic tuning exercise.

---

## Troubleshooting

| Symptom | Most likely cause | Where to look |
|---|---|---|
| Words run ahead of the sound | Route delay not subtracted | `LyricsTimeline`, rule 4 of the lyrics contract. The most likely bug in the project |
| All searches suddenly return nothing | Resolution broken, misreported as "unavailable" | Error classification in `SourceProvider`; switch to the companion provider |
| Search stops working mid-party | Daily allowance exhausted | Something is spending search calls it should not — suggestions are forbidden from doing so |
| Audio blares from the device speaker | FR-018 pause not firing | `OutputRouteMonitor`, `externalOutputLost` handling |
| A microphone prompt appears | A record-capable session was configured | `AudioSessionController`; rule 5 of the audio contract |
| Stutter triggers a reload | Link trouble mistaken for stream trouble | `stalled` must not trigger re-resolution |
| The song just sung is suggested again | Session exclusion missing | Exclusion rule 2 in the recommendation contract |
| App refuses to launch | Signature expired | Re-sign; see research.md R6 |
| Quality lower than expected | Probably the Bluetooth re-encode, not a bug | research.md R0. Check with a cable before investigating code |

---

## Spikes to run before implementation

The spikes in [research.md](./research.md) are prerequisites, not optional investigation.

**S5** runs first — route delay over the actual speaker. Bluetooth is the only supported route, so a missing compensation is wrong for every song, and this is the measurement behind the project's hardest success criterion. **S0** runs alongside it: which codec the link negotiates, and how much quality the link discards. That answer determines how honest the app's quality claims must be and whether S1 is worth effort at all. **S7** follows — background audio, LAN access, and signature validity — because all three are cheap now and expensive to discover late.

No finding marked **[prior]** in research.md may be cited as evidence in a completion report until its spike has run.
