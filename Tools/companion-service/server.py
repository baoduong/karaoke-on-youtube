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
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TIMEOUT_SECONDS = 30


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
            raise RuntimeError(f"yt-dlp exited {result.returncode}: {stderr}")
        return json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"yt-dlp timed out after {TIMEOUT_SECONDS}s")
    except json.JSONDecodeError as e:
        raise RuntimeError(f"yt-dlp output is not valid JSON: {e}")


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

        elif path == "/resolve-renditions":
            video_id = params.get("id", [None])[0]
            if not video_id:
                self._json(400, {"error": "missing id parameter"})
                return
            try:
                result = resolve_renditions(video_id)
                self._json(200, result)
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
