# Karaoke Companion Service

A small HTTP service that wraps `yt-dlp` to resolve YouTube audio renditions and stream addresses server-side.

## Why this exists

On-device resolution (`OnDeviceSourceProvider`) depends on undocumented YouTube internals and breaks periodically. Fixing it requires a rebuild and re-sign of the iOS app — a chore the singer must perform (FR-036). The companion service fixes resolution server-side: update `yt-dlp`, restart the service, done. No rebuild, no re-sign.

## HTTP surface

| Method | Path | Query params | Response |
|--------|------|-------------|----------|
| GET | `/health` | — | `{"status":"ok"}` |
| GET | `/resolve-renditions` | `id=<videoID>` | `{"renditions":[...]}` |
| GET | `/resolve-address` | `id=<videoID>&itag=<itag>` | `{"url":"...","renditionItag":N,"expiresAt":N,"resolvedAt":N,"supportsRangeRequests":true}` |

Response shapes match the iOS `SourceProvider` protocol exactly.

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

## iOS app configuration

In the app's Settings → Companion Service, enter the service address (e.g. `http://192.168.1.10:7979`). The app will use the companion as a fallback when on-device resolution fails.

## Security note

The service has no authentication. Run it only on a trusted local network. The stream URLs it returns are not logged by the service or by the iOS app (data-model invariant 4).
