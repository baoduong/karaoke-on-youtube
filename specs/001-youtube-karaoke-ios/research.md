# Phase 0 Research: YouTube-Sourced Karaoke App

**Feature**: `001-youtube-karaoke-ios` | **Date**: 2026-11-03 | **Spec**: [spec.md](./spec.md)

Resolves every NEEDS CLARIFICATION in [plan.md](./plan.md)'s Technical Context.

**Evidence status.** Findings marked **[verified]** were checked against a live source on 2026-11-03 and the check is reproducible. Findings marked **[prior]** rest on documented platform behaviour but were not executed here; each carries a prescribed verification step and a named spike. Nothing in this document is presented as measured that was not measured. Per Constitution Principle III, every **[prior]** affecting audio, network, or timing must be converted to a device measurement before the requirement it supports is considered met.

---

## R0. The real audio quality ceiling is the Bluetooth link

### Decision

Accept **Bluetooth as the only output route** (user's decision) and design the quality strategy around the fact that the link, not the upstream rendition, sets the ceiling. Report route-induced degradation honestly (FR-014) rather than advertising a bitrate the link discards.

### Rationale

**[prior]** Bluetooth audio is always re-encoded. The app decodes the downloaded stream to PCM, the system re-compresses it for transmission, and the speaker decompresses it again. Because the source is already a lossy stream, this is a lossy-to-lossy transcode — the one stage in the chain that is both unavoidable and lossy on top of existing loss.

Three consequences follow, and they reorder the project's priorities:

1. **The gap between upstream renditions shrinks.** Whatever difference exists between ~128 kbps AAC and ~160 kbps Opus is substantially masked by the re-encode that follows. Chasing the better rendition has a poor return on this route.
2. **A cable would be the single largest quality improvement available** — it removes the re-encode entirely. It is not chosen, by the user's decision, and that is a legitimate trade of fidelity for convenience. It is recorded here so the trade is deliberate rather than accidental.
3. **Effort should move.** Spike S1 (codec decodability) drops from blocking to merely useful. Spike S5 (route delay compensation) rises to the top, because on a Bluetooth-only design a missing compensation is wrong for every song.

### Spike S0 — MEASURED 2026-11-03 **[verified on device]**

iPhone 16 Pro, iOS 26, JBL Flip 6 over Bluetooth, read from `AVAudioSession`:

| Property | Built-in speaker | JBL Flip 6 over Bluetooth |
|---|---|---|
| Port type | `Speaker` | **`BluetoothA2DPOutput`** |
| Sample rate | 48 000 Hz | **44 100 Hz** |
| Output channels | 2 | **2** |
| IO buffer | 21.33 ms | 23.22 ms |
| Reported output latency | 15.4 ms | **112.1 ms** |

**The link negotiates A2DP, not HFP.** iOS exposes no public API naming the transmission codec, so SBC versus AAC cannot be read directly — but the three observable properties settle the question that actually matters. HFP is mono at 8–16 kHz; this route is stereo at 44.1 kHz on an `A2DP` port. The catastrophic case is ruled out.

44.1 kHz is A2DP's native rate, and the source material is 44.1 kHz too, so no resampling is forced by the link. The remaining loss is the re-encode itself, which stands as described above and cannot be measured from inside the app.

**Consequence for effort allocation, now grounded rather than asserted**: the route is healthy A2DP stereo, so the gap between upstream renditions is not being thrown away as badly as the worst case would have it. S1 keeps its lowered priority, but choosing a better rendition is not pointless.

### Alternatives considered

- **Cable to the PA speaker**: materially better audio, rejected by the user for convenience. Recorded as the known-better option.
- **Hiding the degradation**: rejected. Claiming a quality the chain cannot deliver violates Principle VI, and the singer can hear the truth anyway.

---

## R1. Which upstream rendition to request

### Decision

Target **itag 140 (AAC-LC, ~128 kbps, M4A)** as the default rendition. Rank Opus above it *only* if spike S1 proves the platform can decode it; otherwise exclude Opus renditions by marking them undecodable.

Treat the highest-bitrate rendition as the one the device can *actually play*, not the one with the largest number. FR-004's fallback clause exists for this.

**Priority note**: per R0, this decision matters less than it would on a wired route. It is still worth getting right — a worse input is still a worse output — but it no longer blocks other work.

### Rationale

YouTube's audio-only renditions fall into two families:

| itag | Codec | Container | Typical bitrate | Notes |
|---|---|---|---|---|
| 139 | AAC-LC | M4A | ~48 kbps | Too low for a PA speaker |
| 140 | AAC-LC | M4A | ~128 kbps | The reliable default |
| 141 | AAC-LC | M4A | ~256 kbps | Rarely offered |
| 249 | Opus | WebM | ~50 kbps | |
| 250 | Opus | WebM | ~70 kbps | |
| 251 | Opus | WebM | ~160 kbps | Usually the highest-bitrate audio offered |

**[prior]** AVFoundation ships no WebM demuxer. Opus itself is a known format to the platform's audio layer in certain containers, but the Opus renditions YouTube serves are in WebM, and the container is the blocker rather than the codec. If this holds, itag 251 — nominally the best — is unplayable without remuxing, and itag 140 is the practical ceiling.

This single fact decides how honest the app's "highest quality" claim can be, so it is not left as an assumption.

**Verification (Spike S1, day one, before any other audio work)**: fetch one itag 251 stream and one itag 140 stream; attempt to open each through the platform's asset and audio-file APIs; record which succeeds. If Opus-in-WebM fails, additionally test whether remuxing the Opus bitstream into a supported container without re-encoding produces a playable asset — remuxing preserves quality exactly, re-encoding does not, and a lossy-to-lossy transcode would defeat the entire premise.

Outcomes and consequences:

- **Opus plays directly** → rank Opus first; the ceiling is ~160 kbps Opus, meaningfully better than 128 kbps AAC.
- **Opus plays after remux only** → decide whether per-song remux is worth the complexity. Likely yes for saved songs (one-time cost), likely no for streaming.
- **Opus unusable** → itag 140 is the ceiling. Say so plainly in the UI rather than claiming a quality the app cannot deliver, and treat FR-005's quality reporting as the mechanism that keeps the claim honest.

### Alternatives considered

- **Always pick the highest bitrate.** Rejected: picks an undecodable rendition and fails the song.
- **Re-encode Opus to AAC on device.** Rejected outright. A lossy-to-lossy transcode is strictly worse than the 128 kbps AAC already available, and costs CPU to be worse.
- **Prefer the video-bearing muxed stream for its audio.** Rejected: muxed renditions carry lower-quality audio than the best audio-only rendition, and pull video bytes that playback does not need.

---

## R2. Source resolution — YouTubeKit primary, companion service fallback

### Decision

**Primary**: [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) as `OnDeviceSourceProvider`.
**Fallback**: a self-hosted yt-dlp HTTP service as `CompanionSourceProvider`.
**Search**: YouTube Data API v3 when a key is configured; the active provider's own search otherwise.

### Rationale — YouTubeKit **[verified 2026-11-03]**

| Property | Value | Source |
|---|---|---|
| License | MIT | GitHub API |
| Stars | 422 | GitHub API |
| Archived | No | GitHub API |
| Last push | 2026-10-31 | GitHub API |
| Latest release | 0.4.10, 2026-10-25 | GitHub releases |
| 2026 releases | 0.4.6 (Mar), 0.4.7 (Mar), 0.4.8 (Mar), 0.4.9 (Aug), 0.4.10 (Oct) | GitHub releases |
| Platforms | iOS, watchOS, visionOS, tvOS, macOS | repo description |

Actively maintained, permissively licensed, and purpose-built for Apple platforms. Its recent commit subjects are themselves the strongest evidence that Principle II is correct rather than paranoid — the late-October work is about advertisement pre-roll placements in responses and the resulting 403 behaviour. That is upstream defending itself, in real time, in the library's commit log.

### Rationale — the companion fallback is not optional

**[verified 2026-11-03]** yt-dlp's YouTube extractor took **12 commits in the preceding 90 days** (5 in August, 1 in September, 6 in October), including the addition of an entirely new client type. That is roughly weekly churn in the reference implementation maintained by a large team.

The conclusion for a one-person project is direct: on-device extraction *will* break, and each break costs a rebuild **and a re-sign**, which is a chore the singer must physically perform (FR-036). A server-side fix costs none of that. The companion provider is therefore not a theoretical second implementation added to satisfy an architecture rule — it is the path that keeps the app working on a Saturday night when the on-device path broke on Friday.

Companion service contract: a minimal HTTP surface on the singer's own LAN — resolve a video identifier to a rendition list, and resolve an identifier plus itag to a stream address. The same shapes as [source-provider.md](./contracts/source-provider.md), so the router swaps implementations with no caller change.

### Rationale — search via the Data API

**[verified 2026-11-03]** The Data API returns metadata only and exposes no media stream addresses — the current parameter reference for the search endpoint confirms it filters and orders results and returns nothing resembling a media URL. It is the correct tool for search and the wrong tool for playback.

**[verified 2026-11-03]** The same reference states the search endpoint's allowance: **100 calls per day.** That is the binding constraint on this whole area, and it is small enough to design around rather than measure.

**Design consequences**, both forced by that number:

- **Search is submit-driven, not keystroke-driven**, and results are cached per query for the session. Search-as-you-type would exhaust a day's allowance in minutes. This is also the better interaction for a party, where someone types a full title and hands the iPad over.
- **Suggestions may not use search at all** (R8). Spending the allowance on a convenience feature that then breaks the primary one is a bad trade.

If 100 searches a day proves tight in practice, the fallback is provider-native search with the Data API reserved for metadata.

### Alternatives considered

- **XCDYouTubeKit**: long-standing but not current for this problem; YouTubeKit's 2026 release cadence is the deciding difference.
- **Port yt-dlp's extractor to Swift**: rejected. The verified 12-commits-in-90-days churn is the whole argument — a solo maintainer cannot track it.
- **Embed the official player**: rejected by the user's explicit requirement not to depend on the YouTube app, and it would reintroduce advertising.
- **Companion service as primary**: rejected as the default because it requires always-on infrastructure and fails away from home. It is the fallback, and the singer can promote it when the on-device path breaks.

---

## R3. Stream addresses, expiry, and caching

### Decision

Treat every resolved address as short-lived. Re-resolve on a safety margin before expiry rather than on failure. Never persist an address. For offline saves, store decoded-container bytes, not addresses.

### Rationale

**[prior]** YouTube stream addresses are signed and time-limited, and they support HTTP range requests, which is what makes both seeking and resumable download work. The exact validity window is not a documented contract and must not be hardcoded as a constant derived from one observation.

**Verification (Spike S3)**: resolve an address, record the expiry value it carries, then probe it at intervals until it is refused. Compare the observed lifetime against the declared expiry. Set the safety margin from the measurement, and re-check it when the resolution path changes.

The margin matters because FR-007 promises re-resolution is invisible: starting the refresh *after* a failure means the singer hears a gap, which SC-009 and the party both count as a defect.

### Alternatives considered

- **Re-resolve only on playback failure.** Rejected: guarantees an audible gap mid-song.
- **Persist addresses across launches.** Rejected: they are expired by then, and storing them violates data-model invariant 4.
- **Save the muxed video for offline.** Rejected: multiplies storage for video the app does not play.

---

## R4. Playback stack — no audio engine at all

### Decision

Use the **platform's standard media player**. No audio processing graph, no render callbacks, no custom buffering. Session category **playback** — never a record-capable category.

### Rationale

Two scope decisions compounded. Removing the microphone took away the capture path; removing pitch and tempo took away the *only remaining reason* to own an audio processing graph. What is left — stream an HTTP audio asset with range requests, decode it, continue in the background, publish to the now-playing surface, accept transport commands, report position, survive route changes, apply volume — is precisely the system media player's job description.

Building a render-callback graph to reproduce that would add a real-time hazard, a buffering implementation, and a background-audio integration, in exchange for nothing audible. Principle VII settles it.

**The honest consequence**: Constitution Principle I ("The Audio Path Is Sacred") becomes unreachable rather than satisfied. Its forbidden-operations list governs code inside render callbacks, and this design has none. Recorded in [audio-pipeline.md](./contracts/audio-pipeline.md) rather than amended away, because reintroducing any processing brings the principle straight back.

This also retires two previously-planned spikes. The transposition-quality question is moot, and buffer tuning is now the player's business rather than the app's.

### Output route delay — the remaining non-trivial obligation

**[prior]** The audio session exposes the active route's output latency. This is the input to FR-019: the player reports what has been dispatched, while the Bluetooth speaker emits it a sixth of a second or more later. Subtracting the route's reported latency is what keeps the words aligned with what the room actually hears.

**[prior]** Reported latency for third-party Bluetooth hardware is frequently inaccurate, which is why FR-020 layers a manual trim on top.

Because Bluetooth is now the only supported route, this stopped being an edge case. An implementation that omits the subtraction is wrong for every song, with no configuration in which the mistake hides. That promotes S5 to the project's most important measurement.

### Spike S5 — PARTIALLY MEASURED 2026-11-03 **[verified on device]**

iPhone 16 Pro, JBL Flip 6 over Bluetooth A2DP. `AVAudioSession.outputLatency` **reports 112.1 ms**, against 15.4 ms for the built-in speaker. The Bluetooth link therefore adds roughly **97 ms** over the device's own route.

**This is the number `LyricsTimeline` must subtract** (FR-019). Three things follow:

1. **Uncompensated, the words lead the sound by about 112 ms.** That sits just inside SC-008's 150 ms budget, which is a trap rather than a reprieve: it means a broken implementation can pass a casual look while being visibly wrong to anyone watching closely, and it fails outright on any speaker slower than this one. Treat the margin as absent.
2. **The value must be read live, not hardcoded.** 112.1 ms is this speaker on this phone. A different speaker will differ, and research.md R4 already notes third-party hardware misreports.
3. **Reported is not measured.** The remaining half of this spike is the video test, which no API can substitute for.

**Still open — needs a human with a camera**: run RouteProbe's click-and-flash, film the iPhone screen and the room sound together, and read the gap between the white flash and the click. If the filmed gap is close to 112 ms, the system's figure is trustworthy and automatic compensation suffices. If it differs materially, that difference is exactly what FR-020's manual trim exists to cover, and its default should be set from this measurement.

### Alternatives considered

- **An audio engine with a processing graph.** Rejected: nothing left to process.
- **A hand-written pitch shifter.** Moot — pitch shifting was removed from scope.
- **Record-capable session "just in case".** Rejected: it would prompt for microphone access, violating FR-010 and SC-003 for a capability the app does not use.

---

## R5. Synchronized lyrics

### Decision

**LRCLIB** (`lrclib.net`) as the single lyrics provider, disabled until the singer enables it. Line-level highlight always; word-level when the track provides it.

### Rationale **[verified 2026-11-03]**

A live call to `GET https://lrclib.net/api/search?q=…` returned results with **no API key and no authentication**. The response shape carries, per track: an id, track and artist and album names, `duration` in seconds, an `instrumental` flag, a **`hasWordSync`** boolean, a plain-text field, a synced field in standard LRC timestamp form, and a newer structured `lyricsfile` document with explicit `start_ms` and `end_ms` per line.

Three properties make this the right choice:

- **No auth** means no key to provision, no account, and nothing to leak — which suits Principle V.
- **`duration`** in the response is what makes the data model's duration-mismatch rejection rule enforceable. Matching on title alone returns the wrong song often enough to matter, and this field is the check.
- **`hasWordSync`** lets the app decide between word-level and line-level rendering *before* parsing, rather than discovering it halfway through.

### Spike S6 — RESOLVED **[verified 2026-11-03]**

The planning-time HTTP 503 from `/api/get` was transient. Re-tested three consecutive times with artist, track, and duration parameters: **3 of 3 returned HTTP 200**, each in roughly 0.4 s. No rate limiting was triggered. `/api/get-cached` returns 404 and does not exist.

**Decision**: use `/api/get` as the primary lookup with artist, track, and duration. Fall back to `/api/search` with client-side duration filtering when the exact lookup misses. Treat any 429 as `rateLimited` and back off — this is a free community service and hammering it is both rude and self-defeating.

**The more consequential finding**: for a widely-known English-language track, `/api/search` returned 20 results and **zero of the 20 carried word-level timing** (`hasWordSync` false on every one). Line-level synced text was present throughout.

That reframes the feature. Word-level highlighting is not a thing to build and occasionally lack — it is a thing that will almost never have data, and Vietnamese-language karaoke coverage is very unlikely to be better than English. So:

- Line-level highlight is the feature. Build it well.
- Word-level is opportunistic: parse it when `hasWordSync` is true, and never let the UI look broken when it is false, which is the overwhelming majority of the time.
- FR-022's status as a SHOULD rather than a MUST is now justified by a measurement rather than an expectation.

Response fields confirmed available per result: `id`, `name`, `trackName`, `artistName`, `albumName`, `duration` (float seconds), `instrumental`, `hasWordSync`, `plainLyrics`, `syncedLyrics`, `lyricsfile`.

### Supporting rationale

- **[prior]** The LRC format and its word-level extension are the de facto interchange format; the structured `lyricsfile` form LRCLIB also returns is easier to parse correctly and avoids hand-rolling timestamp parsing.
- **[prior]** Word-level coverage is far thinner than line-level coverage, and Vietnamese-language karaoke coverage is likely thinner still. The app must be good with line-level only, and FR-022 is correctly a SHOULD rather than a MUST.
- Most karaoke sources carry the words in the video image already, so this layer is genuinely an enhancement. That is the reason a lyrics failure may never block playback.

### Rendering

**[prior]** The highlight must be driven by a display-refresh callback that *asks* the audio clock for the position, never by a timer that *keeps* a position. A timer accumulates error and drifts; this is the single most common way a karaoke display goes wrong, and the contract forbids it explicitly.

### Alternatives considered

- **Musixmatch**: commercial terms unsuited to a personal sideloaded app with no agreement in place.
- **Bundled lyrics files**: rejected. The app does not host or redistribute lyrics; it fetches on the singer's behalf when they opt in.
- **Extracting words from the video image**: rejected under Principle VII. Enormous effort, poor reliability, and the image already shows the words.

---

## R8. Suggested next songs

### Decision

A **blended, multi-strategy engine** in which local strategies are the dependable backbone and upstream relation data is an optional enhancement layered on top. No strategy spends search quota.

Priority order: upstream-related → same-channel → session co-occurrence → play history → unplayed favourites.

### Rationale — the obvious approach is unavailable **[verified 2026-11-03]**

I fetched the official parameter reference for the Data API's search endpoint. **There is no related-videos parameter in the current list.** The documented filters are `forContentOwner`, `forDeveloper`, and `forMine`; the optional parameters cover channel, type, duration, caption, definition, licence, region, language, topic, ordering, and paging — and nothing for "videos related to this one". The capability was removed and is not coming back.

So the feature the user asked for cannot be built the obvious way. It can still be built, just not from a documented endpoint.

### Rationale — quota makes the second-obvious approach bad too **[verified 2026-11-03]**

The same reference states the search endpoint's quota plainly: **100 calls per day**. 

Generating suggestions by issuing searches would consume that allowance during a single evening — and search is also what the singer needs for the songs they actually came to sing. Spending the scarce resource on a convenience feature that then breaks the primary feature is a bad trade.

Two design consequences follow directly:

- **No suggestion strategy may call the search endpoint.** 
- **Channel enumeration uses the uploads-playlist path instead.** The same reference explicitly recommends that over search for retrieving a channel's videos, and it avoids the search bucket entirely. Convenient that the cheaper path is also the one the platform recommends.

### Rationale — why local strategies carry the feature

Inverting the naive design turns out to be better on every axis that matters here:

| | Upstream-related | Local strategies |
|---|---|---|
| Availability | Undocumented, breaks with resolution | Always |
| Cost | Network, breakage risk | One local query |
| Privacy | Leaves the device | Stays on it (Principle V) |
| Works offline | No | Yes |
| Quality signal | Best when it works | Good, and specific to this group |

**Session co-occurrence** deserves particular note: songs sung together in past sessions are related by this group's actual taste, which no content-based signal captures. It is one local query and tends to produce the suggestions that land best.

**Same-channel** is unusually strong for karaoke specifically. A karaoke channel fixes the arrangement style, key conventions, and on-screen presentation, so a singer who accepted one upload from a channel will usually accept another. This heuristic would be mediocre for general video and is good here.

Together these guarantee FR-025b — the list is never empty for a singer with any history, even with no network at all.

### Spike S8 — RESOLVED: do not build `upstreamRelated` **[verified 2026-11-03]**

I inspected the YouTubeKit 0.4.10 source directly. Searching its entire `Sources/` tree for `watchNext`, `relatedVideo`, `secondaryResults`, `compactVideoRenderer`, `autoplay`, and `endscreen` returned **zero matches**. Its complete public surface is:

```
metadata · videoID · init(videoID:proxies:useOAuth:allowOAuthCache:methods:)
checkAvailability() · ageRestricted · streams · livestreams
```

Streams and metadata. Nothing about what to watch next.

**Decision: skip the strategy entirely. Task T095 is cancelled.**

The reasoning is the cost-benefit the spike was defined to settle. Building it would mean hand-parsing the InnerTube watch-next response — exactly the undocumented surface that R2 measured at 12 commits per 90 days in the reference implementation. So the strategy would:

- break on roughly the same cadence as stream resolution,
- cost a rebuild **and a re-sign** each time, which is a chore performed by hand,
- and sit at priority 1 above four strategies that never break and need no network.

A component that fails weekly, is expensive to fix, and is shadowed by four reliable alternatives is not worth its maintenance. The suggestion engine ships with `sameChannel`, `coOccurrence`, `history`, and `favourite`.

This is the outcome the spike explicitly permitted, and it makes the feature strictly more robust: every remaining strategy works offline, costs no quota, and leaks nothing about the singer's taste.

### Alternatives considered

- **Search-based "more like this"**: rejected on quota, as above.
- **An on-device similarity model over titles**: rejected under Principle VII. Large effort, and co-occurrence plus channel affinity already capture most of the available signal.
- **A third-party recommendation service**: rejected under Principle V. Sending the singer's taste off-device for a convenience feature is not a trade this project makes.

---

## R6. Distribution and signing

### Decision

Target a **paid Apple Developer Program** account. Support a free account as a degraded path, and surface remaining signature validity in the app (FR-036).

### Rationale

**[prior]** The free-account path signs applications for a short window measured in days and caps both registered devices and app identifiers over a rolling period. The paid program issues year-long certificates and much higher device limits. For an app meant to be picked up and used at a party, a weekly re-signing ritual is a genuine product defect, not a minor inconvenience: the failure mode is the app refusing to launch in front of guests.

The annual fee buys the difference between *works until you next remember to plug it in* and *works*. That is the recommendation, and the free path remains supported for anyone unwilling to pay.

**[prior]** Background audio, local networking (needed to reach a companion service on the LAN), and ordinary network access are available to a sideloaded app under either account type. Microphone access is not required at all — FR-010 removed it, which also removes one permission prompt and one privacy-string obligation.

**Verification (Spike S7)**: before committing to the architecture, install a trivial build under the intended account type and confirm three things on a physical device — audio continues when backgrounded and when the screen locks; a request to a LAN address succeeds; and the observed signature validity matches expectation. Each of these is cheap to test and expensive to discover late.

These limits are **version-dependent**. Apple has changed signing and distribution rules repeatedly, and regional rules diverge. Re-confirm against current official documentation at implementation time rather than trusting any figure quoted second-hand.

### Alternatives considered

- **App Store distribution**: incompatible with the feature's premise; ruled out with the user before planning began.
- **Free account as the recommendation**: rejected because the re-signing cadence breaks the app at exactly the moment it is wanted.

---

## R7. Persistence

### Decision

A lightweight local store for metadata; plain files in the app's own storage for saved audio. No store-managed blobs.

### Rationale

The data model is small — a handful of entities, a few hundred rows in realistic use — and single-user. Under Principle VII the simplest thing that holds the invariants wins.

Audio bytes stay out of the database deliberately. The SavedSong state machine requires an atomic move from a staging location into place, which is what satisfies FR-033's promise that a failed save cannot corrupt an existing one. That is natural with files and awkward with database blobs. It also makes the launch-time reconciliation in the data model straightforward: the file system is authoritative for existence, the record for metadata.

### Alternatives considered

- **Audio as database blobs**: rejected — loses atomic placement and complicates the reconciliation.
- **A full server-backed store**: rejected — violates Principle V and solves a problem this app does not have.

---

## Open items carried into implementation

Each is a named spike with a defined outcome. S1 blocks the quality claim and must run first.

| ID | Question | Blocks | Status |
|---|---|---|---|
| **S5** | Route output latency over the actual PA speaker, with and without compensation | FR-019, FR-020, SC-008 | ⏳ **Open — needs the speaker** |
| **S0** | Which codec the Bluetooth link negotiates; size the gap vs a cable | Honest quality claims, effort allocation | ⏳ **Open — needs the speaker** |
| **S7** | Background audio, LAN access, and signature validity on a physical device | FR-015, companion provider, FR-036 | ⏳ **Open — needs a device** |
| **S1** | Can the platform decode Opus-in-WebM, directly or after remux? | FR-004 ranking, SC-004 | ⏳ Open — needs a device |
| **S3** | Observed stream address lifetime vs declared expiry | FR-007 safety margin | ⏳ Open — needs network probing |
| **S8** | Is upstream watch-next data reachable, and worth the churn? | Whether `upstreamRelated` ships | ✅ **Resolved 2026-11-03 — do not build it** |
| **S6** | LRCLIB `/api/get` reliability and rate limits | Lyrics lookup path | ✅ **Resolved 2026-11-03 — `/api/get` is fine** |

Ordered by importance, which the latest scope changes rewrote:

- **S5 is now first.** Bluetooth is the only route, so a missing delay compensation is wrong for every song rather than occasionally. It is also the measurement behind the project's hardest success criterion.
- **S0 is second** because it tells the app how honest to be about quality, and because it determines whether S1 deserves effort at all.
- **S1 dropped from first to fourth.** It blocked everything when the chain was assumed clean; R0 showed the Bluetooth re-encode masks much of what it would buy.
- **Two spikes were retired.** The old S4 (transposition range, buffer tuning) is moot — pitch and tempo processing were removed, and buffering is now the system player's concern. The old S2 (search quota) is **resolved, not retired**: the official reference states 100 calls per day, which R8 treats as a hard design constraint rather than something to measure.

No **[prior]** above may be cited as evidence in a completion report until its spike has run. That is Principle III applied to this document itself.
