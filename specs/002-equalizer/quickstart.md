# Quickstart: Equalizer validation

**Feature**: 002-equalizer | **Date**: 2026-11-03

What has been verified, how to repeat it, and what is still owed on hardware.

---

## Prerequisites

```bash
# Companion service, for anything involving HLS
cd Tools/companion-service && python3 server.py --port 8080

# An iOS 27 simulator — the runtime is not installed by default
xcodebuild -downloadPlatform iOS -buildVersion 27.2
xcrun simctl list -j runtimes      # find the identifier and its one device type
```

The iOS 27.2 runtime shipped with this Xcode supports exactly one simulated
device type, `iPhone Duo`. It boots and runs tests, but **does not render** —
screenshots come back black. Automated tests are the only way to observe it.

---

## Scenario 1 — Gain and headroom logic

Pure logic, no device needed.

```bash
cd Karaoke
xcodebuild -project Karaoke.xcodeproj -scheme Karaoke \
  -destination 'id=<any-simulator>' \
  -only-testing:KaraokeTests/EqualizerSettingsTests test
```

**Expected**: all pass. Covers clamping (including NaN and infinity),
headroom across boost-only / cut-only / mixed / bypassed, transparency in all
four enabled-and-flat combinations, and the SwiftData round trip.

---

## Scenario 2 — The control attaches to a file source

```bash
xcodebuild ... -only-testing:KaraokeTests/EqualizerAttachmentTests test
```

**Expected**: passes on every runtime. Generates a one-second 440 Hz tone,
loads it, and asserts a tap attached. A regression here would otherwise be
silent — the sliders would move and nothing would happen.

---

## Scenario 3 — HLS attachment, and the iOS version boundary

This is the claim the whole feature rests on. Not automated: it needs the
companion service. Reproduce with a temporary test that loads
`http://<host>:8080/hls-manifest?id=<videoID>` as `.hls` and prints
`isEqualizerAvailable`, run against both runtimes.

**Measured 2026-11-03:**

| Source | iOS 26.2 | iOS 27.2 |
|---|---|---|
| local file | `true` | `true` |
| HLS | `false` | `true` |

The `false` is as important as the `true`: it proves the refusal path reports
honestly instead of silently doing nothing, which is what `AVPlayerItem`
itself does.

---

## Scenario 4 — Full suite, both runtimes

```bash
for ID in <ios-26-udid> <ios-27-udid>; do
  xcodebuild -project Karaoke.xcodeproj -scheme Karaoke \
    -destination "id=$ID" -derivedDataPath /tmp/k-$ID test
done
```

**Expected**: 298 tests in 53 suites, exit 0, and **zero** occurrences of
`Restarting after unexpected exit, crash, or test timeout` in the log.

That last check is not decoration. The first implementation passed on iOS
27.2 and crashed the test host partway through on iOS 26.2, because the tap
held an unretained pointer to its owner. Counting passes alone would have
shipped it: the run still reported "243 tests passed".

---

## Still owed, on the device (Principle III)

Simulator results do not count for audio. These remain unverified:

- **SC-015** — a gain change audible within 200 ms with no click, through the
  Bluetooth PA.
- **SC-EQ-2 / SC-007** — bit-identity with the control bypassed, by capture.
- **SC-009** — a two-hour session with the control active, no dropout, no
  unbounded memory growth. The tap runs an `AVAudioEngine` per item; a leak
  there would show up here and nowhere else.
- That the chosen band centres (100 Hz, 1 kHz, 8 kHz) actually help on a real
  PA. They are reasoned, not tested by ear.

To exercise it on the device: play a song, open **Tone** from the player
toolbar, switch it on, and move Bass or Treble. The sheet reports whether the
platform accepted the control for the song currently playing.

A debug shortcut exists for driving it without taps:

```bash
xcrun simctl launch <udid> com.karaoke.personal.Karaoke \
  -companionServiceAddress "http://<host>:8080" \
  -uiDemoSong <videoID> \
  -uiDemoEqualizer "6,0,4"     # bass,mid,treble in dB; opens the sheet
```
