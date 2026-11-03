# Data Model: YouTube-Sourced Karaoke App

**Feature**: `001-youtube-karaoke-ios` | **Phase**: 1 (Design) | **Spec**: [spec.md](./spec.md)

Entities derived from the spec's Key Entities section and the FR set. Persistence technology is recorded in [plan.md](./plan.md); this document defines *what* is stored and the rules it obeys, not *how* it is written to disk.

## Entity Overview

```text
Favourite ──┐
            ├──> Song <──── Queue ──> QueueEntry
SavedSong ──┘      │  ▲
                   │  └──── Suggestion   (transient, regenerated per song)
                   ├──> AudioRendition ──> StreamAddress   (transient, not persisted)
                   └──> LyricsTrack ────> LyricsLine ──> LyricsWord

PerformanceSettings  (singleton, persisted)
PlaybackSession      (singleton, in-memory only)
```

Persistence boundary:

| Persisted across launches | In-memory only (rebuilt each launch) |
|---|---|
| Song (only those referenced by a Favourite, QueueEntry, or SavedSong) | AudioRendition |
| SavedSong | StreamAddress |
| Favourite | PlaybackSession |
| Queue + QueueEntry | Search results |
| PerformanceSettings | Suggestion |
| LyricsTrack (only for SavedSong) | LyricsTrack (for streamed songs) |

A Song with no Favourite, QueueEntry, or SavedSong referencing it is unreferenced and is removed on next launch. This keeps the local store from accumulating every search result ever seen.

---

## Song

A karaoke source the singer can perform. The anchor entity — search results, queue entries, favourites, and saved songs all reference it.

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | String | yes | Upstream video identifier. Primary key. Stable across sessions. |
| `title` | String | yes | As reported upstream. Not normalised — the singer searches for what they saw. |
| `channelName` | String | yes | Uploader. The main signal for whether a result is a real karaoke channel. |
| `durationSeconds` | Int | yes | Used for queue time estimates and to reject absurd results. |
| `thumbnailURL` | URL? | no | Remote. Cached by the image layer, not by this model. |
| `firstSeenAt` | Date | yes | Set on first local persistence. Used for unreferenced-cleanup diagnostics. |
| `lastPlayedAt` | Date? | no | Null until first played. Drives "recently sung". |
| `playCount` | Int | yes | Defaults to 0. Incremented when playback passes the halfway point, not on mere selection. |

**Validation**

- `id` non-empty and matching the upstream identifier shape. A malformed id is rejected at parse time, never persisted.
- `durationSeconds` > 0. Zero or negative means the upstream metadata is unusable; the result is dropped from search output rather than shown.
- `durationSeconds` > 3600 is flagged, not rejected — long compilations are legitimate but trigger the bounded-resolution path (spec edge case: *Very long source*).
- `title` and `channelName` non-empty after trimming.

**Relationships**

- Has many `AudioRendition` (transient, resolved on demand).
- Has zero or one `LyricsTrack`.
- Referenced by zero or one `Favourite`, zero or one `SavedSong`, and any number of `QueueEntry`.

---

## AudioRendition

One audio-only form of a Song. Several exist per Song; exactly one is selected per playback by the rule in FR-004. Never persisted for streamed songs — re-resolved every time, because the upstream set changes.

| Field | Type | Required | Notes |
|---|---|---|---|
| `itag` | Int | yes | Upstream format identifier. Identifies the rendition within its Song. |
| `container` | Container | yes | Enum: `m4a`, `webm`, `mp4`, `other(String)`. |
| `codec` | Codec | yes | Enum: `aac`, `opus`, `vorbis`, `other(String)`. |
| `averageBitrateBps` | Int? | no | Null when upstream omits it — then ranking falls back to `codec` + `container` priors. |
| `sampleRateHz` | Int? | no | |
| `channelCount` | Int? | no | |
| `approximateByteSize` | Int64? | no | Drives the storage estimate shown before a save (FR-031). |
| `isDecodableOnDevice` | Bool | yes | Computed, not reported upstream. Determines eligibility — see Selection Rule. |

**Selection Rule (FR-004, FR-005)**

Given the set of renditions for a Song:

1. Discard every rendition where `isDecodableOnDevice` is false. If the set is now empty, resolution fails with *unavailable format*, distinct from *unavailable song* (FR-008).
2. Rank the remainder by `averageBitrateBps` descending.
3. Break ties by codec preference order, which is a plan-phase decision recorded in [research.md](./research.md) and must not be hardcoded in two places.
4. Break remaining ties by `channelCount` descending, then by `itag` ascending for determinism.
5. Select the first. Record `itag`, `codec`, `container`, and `averageBitrateBps` on the PlaybackSession so FR-005 can report them.

Selection must be a pure function of the rendition set — same input, same output — so SC-004 can be verified by comparing the function's choice against the full set offline.

**Validation**

- `itag` unique within a Song's rendition set. A duplicate indicates a parse fault and fails resolution rather than silently picking one.
- `averageBitrateBps`, when present, > 0.
- `isDecodableOnDevice` is determined by the device's actual decoder capability, not by a hardcoded list, so the answer stays correct across OS versions.

---

## StreamAddress

A time-limited resolved address for fetching an AudioRendition. Transient by nature — the expiry is the entire reason this is a separate entity (FR-007).

| Field | Type | Required | Notes |
|---|---|---|---|
| `url` | URL | yes | Never logged in full, never persisted. |
| `renditionItag` | Int | yes | Which AudioRendition this address serves. |
| `expiresAt` | Date | yes | Parsed from the address, or defaulted conservatively when absent. |
| `resolvedAt` | Date | yes | For diagnosing clock-skew-induced premature expiry. |
| `supportsRangeRequests` | Bool | yes | Gates seek-without-refetch and the save path. |

**Rules**

- An address is considered stale at `expiresAt` minus a safety margin, not at `expiresAt`. The margin is a plan-phase constant; the point is that re-resolution starts before playback would fail, so FR-007 never shows the singer a gap.
- An address is never written to persistent storage. A SavedSong holds bytes, not an address.
- Re-resolution preserves the current playback position and the selected `renditionItag`. If the same itag is no longer offered, the Selection Rule runs again and the change is recorded for FR-005 reporting.

---

## SavedSong

A Song whose selected rendition has been written to device storage (FR-029 … FR-033).

| Field | Type | Required | Notes |
|---|---|---|---|
| `songID` | String | yes | Foreign key to Song. Primary key — one saved copy per Song. |
| `fileRelativePath` | String | yes | Relative to the app's media directory. Absolute paths break across reinstalls. |
| `container` | Container | yes | Copied from the saved AudioRendition. |
| `codec` | Codec | yes | Copied from the saved AudioRendition. |
| `averageBitrateBps` | Int? | no | Copied. Lets FR-030 prove the offline copy matches the online quality. |
| `byteSize` | Int64 | yes | Actual bytes on disk, measured after write — not the upstream estimate. |
| `savedAt` | Date | yes | |
| `state` | SaveState | yes | See state machine below. |
| `downloadedBytes` | Int64 | yes | Progress for FR-029. Equals `byteSize` when complete. |
| `lastError` | String? | no | Populated only in `failed`. Cleared on retry. |

**State machine**

```text
          start save
  (none) ───────────> pending ──────> downloading ──────> complete
                         │                 │                  │
                         │                 ├─ no space ──> failed
                         │                 ├─ network ───> failed
                         │                 └─ cancelled ─> (none)   [partial file deleted]
                         │                                   ▲
                         └───────── cancelled ───────────────┘
                                                        retry
                                              failed ──────────> pending
                                                        delete
                                           complete ──────────> (none)
```

**Rules**

- A `complete` SavedSong is only reachable after the written byte count is verified against the expected size and the file is confirmed decodable. A truncated file must never be marked complete — FR-030 promises offline playback works.
- The partial file for a `downloading` or `failed` entry is written to a staging location and moved into place atomically on completion. This is what satisfies FR-033: a failed save cannot corrupt an existing saved song because it never touches it.
- A save that fails for space leaves `state = failed` with an actionable `lastError`, and leaves every other SavedSong untouched.
- On launch, any entry in `pending` or `downloading` is reconciled: its staging file is checked and the entry either resumes or moves to `failed`. No entry stays in a transient state across launches.
- Deleting a SavedSong removes the file and the record together. An orphaned file with no record, or a record with no file, is repaired at launch — the file system is authoritative for existence, the record for metadata.

**Derived**

- Total storage used (FR-031) = sum of `byteSize` over `complete` entries, plus staging bytes for in-flight entries, reported separately so the singer understands a cancel will reclaim them.

---

## PerformanceSettings

The singer's audio controls. A singleton — one set, applied to whatever is playing, persisted across songs and restarts (FR-028).

| Field | Type | Required | Default | Range |
|---|---|---|---|---|
| `outputVolume` | Double | yes | 1.0 | 0.0 … 1.0 (FR-013) |
| `manualLyricsOffsetMs` | Int | yes | 0 | −2000 … +2000 (FR-020) |
| `lyricsFontScale` | Double | yes | 1.0 | 0.5 … 3.0 (FR-024) |

Three fields. There are no vocal fields — the PA speaker owns the microphone, its effects, and the vocal-versus-music balance in hardware (FR-010). There are no pitch or tempo fields — songs play as published (FR-011).

**Validation**

- Every numeric field is clamped to its range on read as well as on write. A corrupted or hand-edited store must not be able to push an out-of-range value at a party PA; that is a speaker-damage and hearing-safety concern, not merely a bad value.
- `manualLyricsOffsetMs` is a correction *added to* the route's automatically detected delay, not a replacement for it. Resetting it to 0 must restore automatic behaviour. It exists because Bluetooth speakers frequently misreport their own latency.

**Propagation**

Volume changes are ramped so no click occurs, and take effect within the SC-007 budget. No settings change may stop or restart playback. With pitch and tempo processing removed, nothing in this entity touches the decoded samples — the audio reaching the output is the decoded source with level applied and nothing else, which is what SC-007's bit-identity check verifies.

---

## Suggestion

A candidate next song for the song currently playing or just finished (FR-025a … FR-025f). Transient — regenerated whenever the current song changes, never persisted. Caching suggestions would make them stale against a session-exclusion set that changes every few minutes.

| Field | Type | Required | Notes |
|---|---|---|---|
| `songID` | String | yes | Foreign key to a Song. The Song itself is unreferenced until the singer acts on the suggestion. |
| `strategy` | SuggestionStrategy | yes | Which source produced it. Surfaced to the singer (FR-025f). |
| `score` | Double | yes | 0…1 within its strategy. Used for ranking, not shown. |
| `reason` | String | yes | Short, singer-facing: "same channel", "you sang this before", "often sung together". |

```swift
enum SuggestionStrategy {
    case upstreamRelated   // the platform's own "what's next" data
    case sameChannel       // more from the same karaoke channel
    case history           // the singer sang it before and liked it
    case coOccurrence      // sung in the same session as the current song previously
    case favourite         // an unplayed favourite
}
```

**Blending rule**

Strategies are ordered as listed. Candidates are gathered from each, deduplicated by `songID` keeping the highest-priority strategy, filtered through the exclusion rules below, ranked by strategy order then `score`, and truncated to the display limit.

The ordering matters: `upstreamRelated` is the best signal when available, but [research.md](./research.md) R8 establishes it is no longer obtainable through a documented interface and may be absent entirely. Every strategy below it is computable from local data alone, which is what guarantees FR-025b — the list is never empty for a singer who has used the app even briefly.

**Exclusion rules**

1. The currently playing song.
2. Any song in `PlaybackSession.performedSongIDs` — already sung this session (FR-025c). This is the rule whose absence makes a suggestion list visibly stupid.
3. Any song already in the queue as a `waiting` entry; suggesting what is already queued wastes a slot.
4. Any song whose last resolution failed with a content-side error, for the remainder of the session. Suggesting a song known to be unavailable is worse than suggesting nothing.

**Validation**

- `score` in 0…1. A strategy that cannot produce a meaningful score returns a constant; it still ranks below higher-priority strategies.
- `reason` non-empty. A suggestion the singer cannot interpret is noise.
- The result list contains no duplicate `songID`.

**Cold start**

With no history, only `upstreamRelated` and `sameChannel` can contribute. If both are empty the suggestion area shows nothing and says so plainly, rather than presenting an empty list as a loading state. This is the one case where FR-025b cannot be satisfied, and it resolves itself after the first few songs.

---

## Queue and QueueEntry

An ordered list of Songs awaiting performance (FR-025, FR-026). One Queue exists.

**QueueEntry**

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | yes | Own identity — the same Song may appear twice in one queue. |
| `songID` | String | yes | Foreign key to Song. |
| `position` | Int | yes | Zero-based. Contiguous and unique within the Queue. |
| `addedAt` | Date | yes | |
| `state` | QueueEntryState | yes | `waiting`, `current`, `played`, `skipped`, `failed`. |

**Rules**

- At most one entry is `current` at any time.
- `position` is renumbered to stay contiguous after every insert, remove, or reorder. A gap or duplicate is a defect.
- Reordering or removing a non-current entry must not disturb playback of the current entry (FR-025, acceptance 3).
- Removing the `current` entry advances to the next `waiting` entry, exactly as a natural finish would.
- On natural finish, the current entry becomes `played` and the lowest-positioned `waiting` entry becomes `current` (FR-026). If none remains, playback stops and the session ends cleanly.
- An entry whose resolution fails becomes `failed` and the queue advances — one dead song must not stall the party (spec edge case: *Source is withdrawn or restricted*).
- The Queue is persisted so a crash or restart mid-party does not lose it. `current` is restored as `waiting` on launch; the app does not auto-resume audio on cold start.

---

## Favourite

| Field | Type | Required | Notes |
|---|---|---|---|
| `songID` | String | yes | Foreign key to Song. Primary key — a Song is favourited at most once. |
| `addedAt` | Date | yes | Default sort order, newest first. |

Persists across restarts (FR-027). Favouriting pins the Song against unreferenced cleanup.

---

## LyricsTrack, LyricsLine, LyricsWord

Optional synchronized text for a Song (FR-022, FR-023). A Song may have none — most karaoke sources carry the words in the video image, which is handled by the video layer, not by this model.

**LyricsTrack**

| Field | Type | Required | Notes |
|---|---|---|---|
| `songID` | String | yes | Foreign key. One track per Song. |
| `source` | LyricsSource | yes | Which provider supplied it. Needed to re-fetch or invalidate. |
| `hasWordTiming` | Bool | yes | False means line-level highlight only. |
| `globalOffsetMs` | Int | yes | Default 0. Singer-adjustable correction for a track that is uniformly early or late. |
| `fetchedAt` | Date | yes | |

**LyricsLine**

| Field | Type | Required | Notes |
|---|---|---|---|
| `index` | Int | yes | Zero-based, ordered. |
| `startMs` | Int | yes | Milliseconds from song start, before `globalOffsetMs`. |
| `endMs` | Int? | no | Null means "until the next line starts". |
| `text` | String | yes | May be empty — an empty line is a legitimate instrumental gap marker. |

**LyricsWord** (present only when `hasWordTiming`)

| Field | Type | Required | Notes |
|---|---|---|---|
| `lineIndex` | Int | yes | Foreign key to LyricsLine. |
| `index` | Int | yes | Zero-based within the line. |
| `startMs` | Int | yes | |
| `text` | String | yes | Non-empty. |

**Validation**

- `LyricsLine.startMs` strictly increasing across `index`. A track that is not monotonic is rejected at parse time rather than producing jumping highlights.

- `LyricsLine.endMs`, when present, > `startMs` and ≤ the next line's `startMs`.
- `LyricsWord.startMs` strictly increasing within a line, and within the enclosing line's bounds.
- A track whose last `startMs` exceeds the Song's `durationSeconds` by more than a small tolerance is rejected as mismatched — it is almost certainly the wrong song.

**Timing rules (FR-023, SC-008)**

- The audio playback position is the single source of truth for which line and word is current. Wall-clock time and UI timers are never authoritative; they only decide when to *ask* the player for its position.
- Effective time for lookup = playback position − `PlaybackSession.outputLatencyMs` + `globalOffsetMs` + `PerformanceSettings.manualLyricsOffsetMs`.

  The output-latency subtraction is what makes FR-019 work and is the easiest rule here to omit. The playback position reports what has been *dispatched*; the Bluetooth speaker emits it a sixth of a second or more later. Without the subtraction the words run visibly ahead of the sound — and since Bluetooth is now the only supported route, this is not an edge case to handle but the normal path for every song. An implementation that omits it is wrong 100% of the time rather than occasionally.
- On seek, the current line and word are recomputed from the new position in the same update as the seek — not drifted into over subsequent frames.
- Playback rate is always 1.0 (FR-011), so no rate conversion enters the lookup.

---

## PlaybackSession

Live state of one performance. In-memory only — never persisted. Exists so that every view reads one coherent description of what is happening.

| Field | Type | Notes |
|---|---|---|
| `songID` | String? | Null when idle. |
| `selectedRendition` | AudioRendition? | What FR-005 reports. |
| `positionSeconds` | Double | Read from the audio clock, not accumulated from a timer. |
| `durationSeconds` | Double | From the decoded asset, which may differ slightly from Song metadata; the decoded value wins for seek bounds. |
| `state` | SessionState | See state machine. |
| `outputRoute` | OutputRoute | Current route, and whether it degrades quality (FR-014). |
| `outputLatencyMs` | Double | The active route's reported output delay. Subtracted when placing the words (FR-019, FR-020). |
| `isExternalOutputPresent` | Bool | False means audio would play from the device's own speaker — the FR-018 pause trigger. |
| `lastError` | PlaybackError? | Cleared on successful state transition. |
| `performedSongIDs` | Set\<String\> | Songs sung this session. The exclusion set for suggestions (FR-025c). Cleared when the session ends. |

**State machine**

```text
   idle ──select──> resolving ──success──> buffering ──> playing <──┐
     ▲                  │                      │           │  │     │
     │                  │                      │        pause │ resume
     │                  │                      │           ▼  │     │
     │                  │                      │        paused ─────┘
     │                  │                      │           │
     │                  │                      │      interruption
     │                  │                      │           ▼
     │                  │                      │     interrupted ──end──> paused
     │                  │                      │
     │                  ├─ unavailable ──> failed
     │                  └─ mechanism ────> failed
     │                                         │
     └────────── stop / queue empty ───────────┴──── finished ──> (next entry) ──> resolving
```

**Rules**

- `resolving → failed` carries which kind of failure it was, so FR-008 can word it correctly: an unavailable song is the singer's problem to route around, a broken mechanism is the maintainer's.
- A stale StreamAddress detected during `playing` triggers a silent re-resolve that preserves `positionSeconds`; the session does not visibly leave `playing` (FR-007).
- `interrupted` is entered on a system audio interruption and retains `positionSeconds`. On interruption end, the session moves to `paused` and offers resumption rather than auto-resuming (FR-016) — a phone call ending should not blast music at the singer mid-conversation.
- An output route change does not change `state` as long as an external route remains. It updates `outputRoute` and `outputLatencyMs`, and the lyrics layer immediately adopts the new delay (FR-017, FR-019).
- Losing the external route — cable pulled, Bluetooth speaker dropped — sets `isExternalOutputPresent` to false and moves the session to `paused` (FR-018). Audio must not continue out of the device's own speaker at PA volume.
- `finished` triggers the queue advance in QueueEntry's rules. If the queue is empty, the session returns to `idle`.

---

## Cross-Entity Invariants

1. Every `QueueEntry.songID`, `Favourite.songID`, `SavedSong.songID`, and `LyricsTrack.songID` resolves to an existing Song. Orphans are repaired at launch, not tolerated.
2. A Song is retained in the store if and only if it is referenced by a Favourite, a QueueEntry, or a SavedSong. Unreferenced Songs are removed at launch.
3. Deleting a Song's last reference deletes its LyricsTrack and, if present, its SavedSong file.
4. No `StreamAddress` value reaches persistent storage, a log, or an error message shown to the singer.
5. `PerformanceSettings` values are in range at every read, regardless of what the store contains.
6. The sum of `SavedSong.byteSize` over `complete` entries equals the measured size of the media directory minus staging. A divergence indicates an orphaned file and is repaired at launch.
7. Nothing in this model is transmitted to any service operated by this app (FR-035, Constitution Principle V).
