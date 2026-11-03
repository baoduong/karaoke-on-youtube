#!/usr/bin/env bash
# Capture one screenshot per tab from a booted simulator.
#
# The simulator offers no command-line way to tap a tab bar, so the app reads
# a DEBUG-only -uiTab argument instead. Relaunching per tab is slower than
# tapping would be, but it is scriptable and reproducible.
#
# Usage: ./shoot-screens.sh <simulator-udid> [output-dir]

set -euo pipefail

SIM="${1:?usage: shoot-screens.sh <simulator-udid> [output-dir]}"
OUT="${2:-/tmp/ui-shots}"
BUNDLE="com.karaoke.personal.Karaoke"

mkdir -p "$OUT"

shoot() {
  local index="$1" name="$2"
  shift 2
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$SIM" "$BUNDLE" -uiTab "$index" "$@" >/dev/null 2>&1
  sleep "${SETTLE:-5}"
  xcrun simctl io "$SIM" screenshot "$OUT/${name}.png" >/dev/null 2>&1
  echo "  $name"
}

echo "Capturing to $OUT"
shoot 0 01-sing
shoot 1 02-queue
shoot 2 03-library
shoot 3 04-settings
echo "Done."
