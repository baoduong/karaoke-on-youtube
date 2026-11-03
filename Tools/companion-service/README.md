# Karaoke Companion Service

A small HTTP service that wraps `yt-dlp` to resolve YouTube audio renditions and stream addresses server-side.

## Why this exists

On-device resolution (`OnDeviceSourceProvider`) depends on undocumented YouTube internals and breaks periodically. Fixing it requires a rebuild and re-sign of the iOS app — a chore the singer must perform (FR-036). The companion service fixes resolution server-side: update `yt-dlp`, restart the service, done. No rebuild, no re-sign.

## HTTP surface

| Method | Path | Query params | Response |
|--------|------|-------------|----------|
| GET | `/health` | — | `{"status":"ok"}` |
| GET | `/search` | `q=<query>&limit=<n>` | `{"results":[...]}` |
| GET | `/metadata` | `id=<videoID>` | `{"id":"...","title":"...","channelName":"...","durationSeconds":N}` |
| GET | `/related` | `id=<videoID>&limit=<n>` | `{"results":[...]}` — karaoke-filtered |
| GET | `/hls-manifest` | `id=<videoID>&minHeight=<px>` | an HLS master playlist, `application/vnd.apple.mpegurl` |
| GET | `/resolve-renditions` | `id=<videoID>` | `{"renditions":[...]}` |
| GET | `/resolve-address` | `id=<videoID>&itag=<itag>` | `{"url":"...","renditionItag":N,"expiresAt":N,"resolvedAt":N,"supportsRangeRequests":true}` |

Response shapes match the iOS `SourceProvider` protocol exactly.

The service is threaded. A prewarm request takes seconds, and on a
single-threaded server it would sit in front of the tap the singer just made.

## Manifest cache

`/hls-manifest` is the only cached endpoint. Building a manifest runs
`yt-dlp` and measures 3–4 s, so the app warms the cache for the next songs
in the queue and the first suggestions while the current one plays.

What is cached is **not media** — it is roughly 4 KB of text per song, a
playlist naming three `googlevideo.com` URLs. The audio and video never pass
through this service; the phone fetches them from Google directly.

Entries expire from the `expire` stamp carried in those URLs, minus a 15
minute margin so a song starting near the edge still has live URLs for its
whole length. A per-song lock means a prewarm and a tap racing for the same
song run `yt-dlp` once, not twice.

### Known limitation, if this is ever extended

The cache has no bound and no eviction. `_MANIFEST_CACHE` and
`_MANIFEST_KEY_LOCKS` only ever grow: an expired entry stops being served but
is never deleted, and every song ever requested keeps its lock object.

At ~4 KB per song this is roughly 4 MB per thousand songs, which does not
matter for a service that is started for a party and stopped afterwards — the
intended use. It would matter for a long-lived or shared deployment.

The fix is small and deliberately not done yet: sweep expired keys out of both
dictionaries when writing a new entry, or cap the cache and evict the oldest.

## Prerequisites

```bash
brew install yt-dlp   # or: pip install yt-dlp
```

Python 3.10+ (standard library only — no pip packages needed).

## Running

```bash
./run.sh                    # listens on 0.0.0.0:7979
./run.sh --port 8080        # custom port
./run.sh --host 127.0.0.1   # local only
```

## When YouTube starts refusing: cookies

After enough extractions from one address, YouTube answers `Sign in to confirm
you're not a bot` and every endpoint that needs a full extraction returns 500.
Search keeps working, because it uses a shallower path.

```bash
python3 server.py --port 8080 --cookies-from-browser chrome
```

Measured on macOS, 2026-11-03: **Chrome worked. Safari and Edge did not** —
Safari's cookies had already been rotated, Edge was not signed in. Firefox is
usually the easiest because its cookie store is not encrypted, but it was not
installed here.

### Read this before turning it on

**It attaches your Google account to every request.** yt-dlp's own wiki warns
that using account cookies risks the account being restricted. A throwaway
account is the safer choice; your main one is not.

**YouTube rotates the cookies as a security measure**, which signs the browser
out. Safari's failure above was exactly that, from an earlier session.

**It changes what YouTube offers.** This one is not a warning in anyone's
documentation and was found by measurement:

| | Anonymous | Signed in |
|---|---|---|
| HLS audio | separate variant, itag 234 (~129 kbps) | none offered |
| HLS video | separate video-only variants | — |
| HLS muxed | — | itags 91-96, audio and video together |

The split form is preferred and is what the service builds when it is
available. Signed in, it falls back to a muxed variant — verified to carry
both `h264` video and `aac` audio — at some cost in audio bitrate. Without
that fallback, enabling cookies fixes metadata and search while breaking
playback entirely, which is worse than the block it cures.

## iOS app configuration

In the app's Settings → Companion Service, enter the service address (e.g. `http://192.168.1.10:7979`). The app will use the companion as a fallback when on-device resolution fails.

## Security note

The service has no authentication. Run it only on a trusted local network. The stream URLs it returns are not logged by the service or by the iOS app (data-model invariant 4).
