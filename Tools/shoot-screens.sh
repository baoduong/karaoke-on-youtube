#!/usr/bin/env bash
# Capture the app's screens from a booted simulator.
#
# The simulator offers no command-line way to tap a tab bar, so the app reads
# DEBUG-only launch arguments instead. Relaunching per screen is slower than
# tapping would be, but it is scriptable and reproducible.
#
# Arguments the app understands (all DEBUG-only, see RootView.swift):
#   -uiTab <0-3>                       initial tab
#   -uiDemoSearch <query>              run a search
#   -uiDemoSong <videoID>              start a song — the only scriptable way
#                                      into the player
#   -uiDemoEqualizer <bass,mid,treble> open the tone control with bands moved
#
# Orientation is deliberately NOT scripted here. `xcrun simctl ui` has no
# orientation option, and rotation behaviour around AVPlayer is exactly the
# kind of claim the constitution's Principle III says must be measured on real
# hardware. Landscape belongs to the physical-device tier in
# specs/003-iphone-ipad-interface/quickstart.md, not to this script.
#
# Usage: ./shoot-screens.sh <simulator-udid> [output-dir] [demo-video-id]

set -euo pipefail

SIM="${1:?usage: shoot-screens.sh <simulator-udid> [output-dir] [demo-video-id]}"
OUT="${2:-/tmp/ui-shots}"
SONG="${3:-}"
BUNDLE="com.karaoke.personal.Karaoke"

mkdir -p "$OUT"

shoot() {
  local name="$1"
  shift
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$SIM" "$BUNDLE" "$@" >/dev/null 2>&1
  sleep "${SETTLE:-5}"
  xcrun simctl io "$SIM" screenshot "$OUT/${name}.png" >/dev/null 2>&1
  echo "  $name"
}

echo "Capturing to $OUT"

# One per tab.
shoot 01-sing     -uiTab 0
shoot 02-queue    -uiTab 1
shoot 03-library  -uiTab 2
shoot 04-settings -uiTab 3

# Search results, so row typography can be checked against real titles.
shoot 05-search-results -uiTab 0 -uiDemoSearch "karaoke tone nam"

if [ -n "$SONG" ]; then
  # The player. Proves the video is the largest element and that the
  # transport does not scroll away — contracts/player-layout.md C-P2, C-P3.
  shoot 06-player -uiTab 0 -uiDemoSong "$SONG"

  # The player with the tone control open. This is the capture that proves
  # C-P1: nothing overlaps or dims the video while a song is playing.
  shoot 07-player-tone -uiTab 0 -uiDemoSong "$SONG" -uiDemoEqualizer 3,0,-2
else
  echo "  (skipping player captures — pass a demo video id as the third argument)"
fi

echo "Done."
