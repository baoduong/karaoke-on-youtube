#!/usr/bin/env python3
"""
Companion service for the Karaoke app.

Wraps yt-dlp to expose resolve-renditions and resolve-address over HTTP,
with the same response shapes as the iOS SourceProvider protocol.

Runs on the singer's own machine (not on iOS). The iOS app calls this when
on-device resolution breaks, avoiding a rebuild-and-re-sign (FR-036, T134).

Endpoints:
  GET /health
  GET /resolve-renditions?id=<videoID>
  GET /resolve-address?id=<videoID>&itag=<itag>

Usage:
  python3 server.py [--port 7979] [--host 0.0.0.0]
"""

import argparse
import json
import subprocess
import sys
import time
import re
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TIMEOUT_SECONDS = 30


class ContentUnavailable(Exception):
    """The upstream explicitly said this video cannot be played.

    Separate from every other failure on purpose. A removed or private video
    is the singer's problem to route around; a parser that stopped working is
    the maintainer's. Reporting the first as a server error — which is what
    happens if yt-dlp's exit status is all we look at — makes a broken
    extractor and an ordinary deleted upload indistinguishable, and that is
    the one confusion the error taxonomy exists to prevent.
    """

    def __init__(self, reason: str, detail: str):
        super().__init__(detail)
        self.reason = reason
        self.detail = detail


# Matched against yt-dlp's stderr. Order matters: the more specific phrases
# must be tested before the generic "unavailable".
_CONTENT_SIGNATURES = [
    ("private", ("private video", "this video is private")),
    ("members_only", ("members-only", "join this channel")),
    ("age_restricted", ("confirm your age", "age-restricted", "inappropriate for some users")),
    ("region_blocked", ("not made this video available in your country", "blocked it in your country")),
    ("live_stream", ("this live event", "premieres in", "is a live stream")),
    ("removed", ("has been removed", "account associated with this video has been terminated")),
    ("not_found", ("video is unavailable", "video unavailable", "does not exist", "incomplete youtube id")),
]


def classify_upstream_failure(message: str) -> ContentUnavailable | None:
    lowered = message.lower()
    for reason, needles in _CONTENT_SIGNATURES:
        if any(needle in lowered for needle in needles):
            return ContentUnavailable(reason, message.strip())
    return None


def run_ytdlp(args: list[str]) -> dict:
    """Run yt-dlp with the given args and return parsed JSON output."""
    cmd = ["yt-dlp", "--no-warnings", "--quiet"] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
        if result.returncode != 0:
            stderr = result.stderr.strip()
            if content_error := classify_upstream_failure(stderr):
                raise content_error
            raise RuntimeError(f"yt-dlp exited {result.returncode}: {stderr}")
        return json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"yt-dlp timed out after {TIMEOUT_SECONDS}s")
    except json.JSONDecodeError as e:
        raise RuntimeError(f"yt-dlp output is not valid JSON: {e}")


def run_ytdlp_lines(args: list[str]) -> list[dict]:
    """Run yt-dlp expecting one JSON object per line, as search results are."""
    cmd = ["yt-dlp", "--no-warnings", "--quiet"] + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
        if result.returncode != 0:
            stderr = result.stderr.strip()
            if content_error := classify_upstream_failure(stderr):
                raise content_error
            raise RuntimeError(f"yt-dlp exited {result.returncode}: {stderr}")
        return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"yt-dlp timed out after {TIMEOUT_SECONDS}s")
    except json.JSONDecodeError as e:
        raise RuntimeError(f"yt-dlp output is not valid JSON: {e}")


def search(query: str, limit: int) -> dict:
    """
    Search YouTube with no API key and no daily quota.

    This exists because the Data API allows only 100 searches per day, which a
    single party exhausts. yt-dlp's ytsearch drives YouTube's own search, so
    coverage matches what a browser would show — including the Vietnamese
    karaoke channels the Data API ranks poorly.

    --flat-playlist keeps this to one request: it returns search metadata
    without resolving each result's formats, which would otherwise mean one
    full extraction per hit.
    """
    limit = max(1, min(limit, 50))
    entries = run_ytdlp_lines([
        f"ytsearch{limit}:{query}",
        "--flat-playlist",
        "--dump-json",
    ])

    results = []
    for entry in entries:
        video_id = entry.get("id")
        duration = entry.get("duration")
        # Songs without a usable duration are dropped rather than passed on:
        # Song validation rejects a non-positive duration, so forwarding one
        # would make the result vanish later with no explanation.
        if not video_id or not duration:
            continue
        results.append({
            "id": video_id,
            "title": entry.get("title") or "",
            "channelName": entry.get("channel") or entry.get("uploader") or "",
            "durationSeconds": int(duration),
            "thumbnailURL": entry.get("thumbnails", [{}])[-1].get("url") if entry.get("thumbnails") else None,
        })
    return {"results": results}


def metadata(video_id: str) -> dict:
    """Full metadata for one video, including the duration and channel that
    the on-device resolver cannot read."""
    info = run_ytdlp([f"https://www.youtube.com/watch?v={video_id}", "--dump-json", "--skip-download"])
    duration = info.get("duration")
    if not duration:
        raise RuntimeError("upstream returned no duration")
    return {
        "id": video_id,
        "title": info.get("title") or "",
        "channelName": info.get("channel") or info.get("uploader") or "",
        "durationSeconds": int(duration),
        "thumbnailURL": info.get("thumbnail"),
    }


MIN_VIDEO_HEIGHT = 720

WATCH_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)


def related(video_id: str, limit: int = 20) -> dict:
    """
    The platform's own "what's next" list for a video.

    There is no public API for this. The web client embeds it in the watch
    page as `ytInitialData` and pages further results through its private
    InnerTube endpoint, so the only way to read it is to parse that blob.

    This lives in the service, not in the app, precisely because it will
    break. YouTube recently moved these entries from `compactVideoRenderer`
    to `lockupViewModel` — a rename that silently broke every consumer
    written against the old name. When the next rename lands, fixing it here
    is a file edit on the user's own machine; fixing it in the app would mean
    a rebuild and a re-signing by hand.
    """
    request = urllib.request.Request(
        f"https://www.youtube.com/watch?v={video_id}",
        headers={"User-Agent": WATCH_UA, "Accept-Language": "en-US,en;q=0.9"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            html = response.read().decode("utf-8", errors="ignore")
    except Exception as exc:
        raise RuntimeError(f"could not fetch watch page: {exc}")

    match = re.search(r"var ytInitialData\s*=\s*(\{.*?\});\s*</script>", html, re.S)
    if not match:
        raise RuntimeError("watch page carries no ytInitialData")

    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"ytInitialData is not valid JSON: {exc}")

    try:
        sections = (
            data["contents"]["twoColumnWatchNextResults"]
            ["secondaryResults"]["secondaryResults"]["results"]
        )
    except (KeyError, TypeError):
        raise RuntimeError("watch page shape changed: no secondaryResults")

    entries = []
    for section in sections:
        entries.extend(section.get("itemSectionRenderer", {}).get("contents", []))

    results = []
    saw_lockup = False
    for entry in entries:
        lockup = entry.get("lockupViewModel")
        if not lockup or lockup.get("contentType") != "LOCKUP_CONTENT_TYPE_VIDEO":
            continue
        saw_lockup = True
        candidate = _lockup_to_result(lockup, exclude_id=video_id)
        if candidate:
            results.append(candidate)
        if len(results) >= limit:
            break

    # An empty list after seeing lockups is a legitimate answer; seeing none at
    # all means the page shape moved again and the parse needs revisiting.
    if not saw_lockup:
        raise RuntimeError("watch page shape changed: no lockupViewModel entries")

    return {"results": results}


# YouTube's related list for a karaoke upload is mostly not karaoke. A sample
# of five returned one karaoke track alongside a film review, a news digest and
# two music compilations. Unfiltered, this strategy would push that in above
# four local strategies that only ever suggest things the singer can sing.
_KARAOKE_MARKERS = (
    "karaoke", "beat", "tone nam", "tone nu", "tone nữ", "karaoke AI",
    "nhac song", "nhạc sống", "phoi moi", "phối mới", "khong loi", "không lời",
)

# A backing track runs a few minutes. Anything past this is a compilation, a
# livestream or a film, none of which belong in a queue.
_MAX_KARAOKE_SECONDS = 15 * 60


def _looks_like_karaoke(title: str, duration: int) -> bool:
    if duration <= 0 or duration > _MAX_KARAOKE_SECONDS:
        return False
    lowered = title.lower()
    return any(marker in lowered for marker in _KARAOKE_MARKERS)


def _lockup_to_result(lockup: dict, exclude_id: str) -> dict | None:
    video_id = lockup.get("contentId")
    if not video_id or video_id == exclude_id:
        return None

    metadata = lockup.get("metadata", {}).get("lockupMetadataViewModel", {})
    title = metadata.get("title", {}).get("content") or ""

    channel = ""
    rows = metadata.get("metadata", {}).get("contentMetadataViewModel", {}).get("metadataRows", [])
    if rows:
        parts = rows[0].get("metadataParts", [])
        for part in parts:
            text = part.get("text", {}).get("content")
            if text:
                channel = text
                break

    duration = _duration_from_overlays(
        lockup.get("contentImage", {}).get("thumbnailViewModel", {}).get("overlays", [])
    )

    # Duration is required rather than optional: Song validation rejects a
    # non-positive value, so an entry without one would be dropped later with
    # nothing to explain its disappearance.
    if not title or not duration:
        return None
    if not _looks_like_karaoke(title, duration):
        return None

    return {
        "id": video_id,
        "title": title,
        "channelName": channel or "Unknown",
        "durationSeconds": duration,
        "thumbnailURL": f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
    }


def _duration_from_overlays(overlays: list) -> int:
    """Reads the duration badge, which carries 'm:ss' or 'h:mm:ss'."""
    for overlay in overlays:
        badges = overlay.get("thumbnailBottomOverlayViewModel", {}).get("badges", [])
        for badge in badges:
            text = badge.get("thumbnailBadgeViewModel", {}).get("text", "")
            seconds = _parse_clock(text)
            if seconds:
                return seconds
    return 0


def _parse_clock(text: str) -> int:
    pieces = text.strip().split(":")
    if not 2 <= len(pieces) <= 3 or not all(p.isdigit() for p in pieces):
        return 0
    total = 0
    for piece in pieces:
        total = total * 60 + int(piece)
    return total


def hls_manifest(video_id: str, min_height: int = MIN_VIDEO_HEIGHT) -> str:
    """
    Build an HLS master playlist pairing YouTube's video variants with its
    high-quality audio variant.

    Most karaoke uploads burn the words into the picture, so the video is the
    lyrics. The obvious way to get both — YouTube's single muxed format,
    itag 18 — carries audio at only 44 kbps against itag 140's 129 kbps, which
    is audible on a PA at volume.

    HLS avoids the trade entirely: its audio variant is backed by itag 140, so
    the stream carries full-quality audio *and* video, and AVFoundation
    handles A/V sync natively rather than us synchronising two players.

    Only H.264 variants are offered. VP9 appears at the same resolutions but
    is not reliably hardware-decoded on Apple platforms, and dropping to
    software decode during a two-hour session is not worth the bitrate.
    """
    info = run_ytdlp([
        f"https://www.youtube.com/watch?v={video_id}",
        "--dump-json", "--skip-download",
    ])

    audio_url = None
    videos = []
    for fmt in info.get("formats", []):
        if "m3u8" not in str(fmt.get("protocol", "")):
            continue
        has_video = fmt.get("vcodec", "none") != "none"
        if not has_video:
            # 234 is the high-quality audio variant; 233 is the low one.
            if fmt.get("format_id") == "234":
                audio_url = fmt.get("url")
            continue
        height = fmt.get("height") or 0
        vcodec = str(fmt.get("vcodec") or "")
        if height >= min_height and vcodec.startswith("avc1"):
            videos.append(fmt)

    if not audio_url:
        raise LookupError("no HLS audio variant available for this video")
    if not videos:
        raise LookupError(f"no H.264 HLS video variant at {min_height}p or above")

    videos.sort(key=lambda f: f.get("height") or 0)

    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-INDEPENDENT-SEGMENTS",
        f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Audio",'
        f'DEFAULT=YES,AUTOSELECT=YES,URI="{audio_url}"',
    ]
    for fmt in videos:
        video_kbps = fmt.get("tbr") or 0
        bandwidth = int((video_kbps + 130) * 1000)
        lines.append(
            f"#EXT-X-STREAM-INF:BANDWIDTH={bandwidth},"
            f'RESOLUTION={fmt.get("width")}x{fmt.get("height")},'
            f'CODECS="{fmt.get("vcodec")},mp4a.40.2",AUDIO="aud"'
        )
        lines.append(fmt.get("url"))

    return "\n".join(lines) + "\n"


def resolve_renditions(video_id: str) -> dict:
    """
    Return all audio-only renditions for a video.

    Response shape matches AudioRendition in the iOS app:
    {
      "renditions": [
        {
          "itag": 251,
          "container": "webm",
          "codec": "opus",
          "averageBitrateBps": 128000,
          "isDecodableOnDevice": true
        },
        ...
      ]
    }

    isDecodableOnDevice is always true here — the server does not know the
    device's decoder capabilities. The iOS app re-checks with DecodabilityProbe.
    """
    info = run_ytdlp([
        "--dump-json",
        "--no-playlist",
        f"https://www.youtube.com/watch?v={video_id}",
    ])

    formats = info.get("formats", [])
    renditions = []

    for fmt in formats:
        # Audio-only: has acodec, no vcodec (or vcodec is "none")
        acodec = fmt.get("acodec", "none")
        vcodec = fmt.get("vcodec", "none")
        if acodec == "none" or vcodec != "none":
            continue

        itag = fmt.get("format_id")
        try:
            itag = int(itag)
        except (TypeError, ValueError):
            continue

        ext = fmt.get("ext", "unknown")
        container = _map_container(ext)
        codec = _map_codec(acodec)

        abr = fmt.get("abr")
        tbr = fmt.get("tbr")
        bitrate_bps = None
        if abr is not None:
            bitrate_bps = int(abr * 1000)
        elif tbr is not None:
            bitrate_bps = int(tbr * 1000)

        renditions.append({
            "itag": itag,
            "container": container,
            "codec": codec,
            "averageBitrateBps": bitrate_bps,
            "isDecodableOnDevice": True,
        })

    return {"renditions": renditions}


def resolve_address(video_id: str, itag: int) -> dict:
    """
    Return a playable stream address for one rendition.

    Response shape matches StreamAddress in the iOS app:
    {
      "url": "https://...",
      "renditionItag": 251,
      "expiresAt": 1234567890.0,
      "resolvedAt": 1234567800.0,
      "supportsRangeRequests": true
    }

    The URL is returned in full — the iOS app never logs it (data-model
    invariant 4). The server does not log it either.
    """
    info = run_ytdlp([
        "--dump-json",
        "--no-playlist",
        f"https://www.youtube.com/watch?v={video_id}",
    ])

    formats = info.get("formats", [])
    target = None
    for fmt in formats:
        try:
            fmt_itag = int(fmt.get("format_id", -1))
        except (TypeError, ValueError):
            continue
        if fmt_itag == itag:
            target = fmt
            break

    if target is None:
        raise LookupError(f"itag {itag} not found for video {video_id}")

    url = target.get("url")
    if not url:
        raise RuntimeError(f"yt-dlp returned no URL for itag {itag}")

    resolved_at = time.time()
    expires_at = _parse_expiry(url, resolved_at)

    return {
        "url": url,
        "renditionItag": itag,
        "expiresAt": expires_at,
        "resolvedAt": resolved_at,
        "supportsRangeRequests": True,
    }


def _map_container(ext: str) -> str:
    mapping = {"m4a": "m4a", "webm": "webm", "mp4": "mp4"}
    return mapping.get(ext, ext)


def _map_codec(acodec: str) -> str:
    if acodec.startswith("mp4a"):
        return "aac"
    if acodec == "opus":
        return "opus"
    if acodec == "vorbis":
        return "vorbis"
    return acodec


def _parse_expiry(url: str, resolved_at: float) -> float:
    from urllib.parse import urlparse, parse_qs
    parsed = urlparse(url)
    params = parse_qs(parsed.query)
    expire_values = params.get("expire", [])
    if expire_values:
        try:
            return float(expire_values[0])
        except ValueError:
            pass
    # Conservative default: 5 minutes from now.
    return resolved_at + 300


class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        # Suppress default access log — it would print stream URLs.
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path == "/health":
            self._json(200, {"status": "ok"})

        elif path == "/related":
            video_id = params.get("id", [None])[0]
            if not video_id:
                self._json(400, {"error": "missing id parameter"})
                return
            try:
                limit = int(params.get("limit", ["20"])[0])
            except ValueError:
                self._json(400, {"error": "limit must be an integer"})
                return
            try:
                self._json(200, related(video_id, limit))
            except ContentUnavailable as exc:
                self._json(404, {"error": exc.detail, "reason": exc.reason})
            except Exception as exc:
                self._json(500, {"error": str(exc)})

        elif path == "/search":
            query = params.get("q", [None])[0]
            if not query:
                self._json(400, {"error": "missing q parameter"})
                return
            try:
                limit = int(params.get("limit", ["20"])[0])
            except ValueError:
                self._json(400, {"error": "limit must be an integer"})
                return
            try:
                self._json(200, search(query, limit))
            except ContentUnavailable as exc:
                self._json(404, {"error": exc.detail, "reason": exc.reason})
            except Exception as exc:
                self._json(500, {"error": str(exc)})

        elif path == "/metadata":
            video_id = params.get("id", [None])[0]
            if not video_id:
                self._json(400, {"error": "missing id parameter"})
                return
            try:
                self._json(200, metadata(video_id))
            except ContentUnavailable as exc:
                self._json(404, {"error": exc.detail, "reason": exc.reason})
            except Exception as exc:
                self._json(500, {"error": str(exc)})

        elif path == "/hls-manifest":
            video_id = params.get("id", [None])[0]
            if not video_id:
                self._json(400, {"error": "missing id parameter"})
                return
            try:
                min_height = int(params.get("minHeight", [str(MIN_VIDEO_HEIGHT)])[0])
            except ValueError:
                self._json(400, {"error": "minHeight must be an integer"})
                return
            try:
                body = hls_manifest(video_id, min_height).encode()
            except LookupError as exc:
                self._json(404, {"error": str(exc)})
                return
            except ContentUnavailable as exc:
                self._json(404, {"error": exc.detail, "reason": exc.reason})
            except Exception as exc:
                self._json(500, {"error": str(exc)})
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.apple.mpegurl")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        elif path == "/resolve-renditions":
            video_id = params.get("id", [None])[0]
            if not video_id:
                self._json(400, {"error": "missing id parameter"})
                return
            try:
                result = resolve_renditions(video_id)
                self._json(200, result)
            except ContentUnavailable as exc:
                self._json(404, {"error": exc.detail, "reason": exc.reason})
            except Exception as exc:
                self._json(500, {"error": str(exc)})

        elif path == "/resolve-address":
            video_id = params.get("id", [None])[0]
            itag_str = params.get("itag", [None])[0]
            if not video_id or not itag_str:
                self._json(400, {"error": "missing id or itag parameter"})
                return
            try:
                itag = int(itag_str)
            except ValueError:
                self._json(400, {"error": "itag must be an integer"})
                return
            try:
                result = resolve_address(video_id, itag)
                self._json(200, result)
            except LookupError as exc:
                self._json(404, {"error": str(exc)})
            except ContentUnavailable as exc:
                self._json(404, {"error": exc.detail, "reason": exc.reason})
            except Exception as exc:
                self._json(500, {"error": str(exc)})

        else:
            self._json(404, {"error": "not found"})

    def _json(self, status: int, body: dict):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main():
    parser = argparse.ArgumentParser(description="Karaoke companion service")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=7979, help="Port (default: 7979)")
    args = parser.parse_args()

    server = HTTPServer((args.host, args.port), Handler)
    print(f"Companion service listening on {args.host}:{args.port}")
    print("Endpoints: /health  /resolve-renditions?id=  /resolve-address?id=&itag=")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)


if __name__ == "__main__":
    main()
