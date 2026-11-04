# Quickstart: Validating the iPhone Interface Work

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04

How to prove this feature works. Most of it cannot be proved by a test runner: nine of the
fourteen success criteria are about what a person sees and reaches, and Principle III says a
simulator result does not count for those. This guide separates the two honestly.

Scope is the iPhone. Stories 4 and 5 are deferred and nothing here validates the iPad.

---

## Prerequisites

- Xcode with an iOS 17 SDK, and `xcodegen` on the path.
- A physical iPhone, enrolled for development, with a valid signing team.
- A microphone, or any object that occupies one hand convincingly.
- A room that can be made dim.
- A Bluetooth speaker, since the device's own speaker is not how this app is used.

Regenerate the project after any change to `project.yml` — the `.xcodeproj` is a build
artifact and is gitignored:

```bash
cd Karaoke && xcodegen generate
```

---

## Tier 1 — Mechanical checks

These run without a device and must pass before anything else is worth doing.

### Build

```bash
cd Karaoke
xcodebuild -scheme Karaoke -destination 'generic/platform=iOS' build
```

Expected: success, with **no new warnings**. Quality Gate 1.

### Test suite

```bash
cd Karaoke
xcodebuild -scheme Karaoke -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test
```

Expected: all existing tests pass, plus the one test this feature adds.

### The one new automated test — SC-007

The single thing in this feature that can rot silently is the rule that no call site writes a
raw text size. It is checked mechanically, not by eye.

The test fails if any of these appears anywhere under `Karaoke/Karaoke/` outside
`KaraokeTheme.swift`:

- `.font(.system(size:`
- `.font(.custom(`
- `.font(Font(`
- a bare system text style, such as `.font(.headline)` or `.font(.body)`

The baseline to beat, measured today:

```bash
grep -rn '\.font(\.system(size:' Karaoke/Karaoke --include='*.swift' | wc -l
# today: 7    required after this feature: 0
```

Contract: `contracts/typography.md` C-T1.

---

## Tier 2 — Simulator captures

The simulator cannot judge legibility, but it can prove that nothing covers the video, and it
can do so reproducibly. The app already carries DEBUG-only launch arguments for exactly this
reason, because the simulator cannot be tapped from a command line.

| Argument | Effect |
|---|---|
| `-uiTab <0-3>` | Opens on a given tab |
| `-uiDemoSearch <query>` | Runs a search so result rows can be inspected with real titles |
| `-uiDemoSong <videoID>` | Starts a song, which is the only scriptable way into the player |
| `-uiDemoEqualizer <bass,mid,treble>` | Opens the tone control with its bands already moved |

### Existing capture, one screenshot per tab

```bash
xcrun simctl list devices booted          # take the UDID
./Tools/shoot-screens.sh <udid> /tmp/ui-before
```

Capture this **before** starting work, so there is something to compare against.

### Captures this feature needs added

`shoot-screens.sh` today captures only the four tabs; it never reaches the player, which is
where Stories 1 and 2 live. Extend it to also capture, using the arguments above:

| Capture | Launch arguments | Proves |
|---|---|---|
| Player, portrait | `-uiTab 0 -uiDemoSong <id>` | C-P2, C-P3 |
| Player with tone open, portrait | `-uiTab 0 -uiDemoSong <id> -uiDemoEqualizer 3,0,-2` | **C-P1** — the video is whole and undimmed with the panel open |
| Any list at the largest text size | `-uiTab 1`, device text size at `.accessibility5` | SC-008 |

**Orientation is not scriptable here.** `xcrun simctl ui` has no orientation option — a
claim this guide previously made and which is wrong. Rotation behaviour around `AVPlayer` is
also precisely the kind of thing Principle III says must be measured on real hardware, so
landscape moved to Tier 3 below rather than being faked in the simulator.

### What to look for in each capture

- The full 16:9 frame is present, with no element on top of it and no dimming layer over it.
- The transport is visible without scrolling.
- At `.accessibility5`, no label is clipped and no control has been pushed off screen.

---

## Tier 3 — Physical device, by a person

Nothing below can be delegated to a machine. Each item names the success criterion it closes.

### Legibility — Story 1

| Check | Criterion |
|---|---|
| Dim the room. Start a song. Sing it from beginning to end reading only the phone, at the distance you would actually hold it. No leaning in, no squinting. | **SC-001** |
| Mid-song, open the tone control and adjust all three bands. The words stay fully visible and undimmed the whole time. | **SC-002** |
| Mid-song, turn the phone on its side. The video gets bigger, the song does not stop, does not restart, and does not lose its place. Repeat several times. | **SC-003** |
| Lay the phone flat on the table, face up, while playing in landscape. The layout does not change. | C-P5 |

### Reach — Story 2

| Check | Criterion |
|---|---|
| Hold a real microphone in one hand and the phone in the other. Operate play/pause, both seeks, next song, and the tone control. No grip change, no second hand, no scrolling. | **SC-005** |
| Scroll whatever sits below the video to its end. The transport has not moved. | **SC-006** |
| Note whether your own hand hides the control you are pressing. | Story 2, scenario 4 |

### Consistency — Story 3

| Check | Criterion |
|---|---|
| Walk every screen. No screen shows two navigation bars or two titles, and the favourites list appears in one place only. | **SC-010** |
| Put the signing-validity screen beside any other screen. They look like the same app. | Story 3, scenario 2 |
| Set the system text size to its largest. Walk every screen: nothing clipped, nothing overflowing, nothing pushed off screen — and the video is no smaller than it was at the default. | **SC-008** |
| Set the display to greyscale. Every state is still distinguishable. | **SC-009**, C-T7 |
| Measure the contrast of each text and glyph colour against its surface, including labels on filled accent controls. | **SC-009** |
| Hand the phone to someone who has never used the app, in a dim room, and ask them to find and start a named song. Time it. | **SC-013** |

### Quality Gate 7 — everything is reachable and everything responds

| Check | Criterion |
|---|---|
| Open every screen from a running app. Operate every control on each one — press it, do not merely look at it. The next-song control and the relocated tone control are new and must both be operated. | **SC-014** |

### Release bar

Before calling this done on a device used for actual singing: one continuous session of at
least **thirty minutes** with no crash, no dropout, and no advertisement. Rotate the device at
least twice during it.

---

## Not validated here

- Anything about the iPad. Stories 4 and 5 are deferred; the iPad keeps its current stretched
  layout and this guide makes no claim about it.
- Pitch or key change. Out of scope by design — see `spec.md` Assumptions.
