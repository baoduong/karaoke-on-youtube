#!/usr/bin/env bash
# run.sh — start the Karaoke companion service.
#
# Prerequisites:
#   brew install yt-dlp   (or pip install yt-dlp)
#   python3 (3.10+)
#
# Usage:
#   ./run.sh [--port 7979] [--host 0.0.0.0]
#
# The service listens on all interfaces by default so the iPhone can reach it
# over the local Wi-Fi network. Restrict to 127.0.0.1 if you only want local
# access (e.g. when using a VPN or SSH tunnel from the phone).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v yt-dlp &>/dev/null; then
    echo "Error: yt-dlp not found. Install with: brew install yt-dlp" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found." >&2
    exit 1
fi

exec python3 "$SCRIPT_DIR/server.py" "$@"
