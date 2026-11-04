# Phase 1 Data Model: Professional iPhone and iPad Interface

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04

This feature stores nothing. "Data model" here means the design tokens and the small pieces of
view state that the interface is built from. All of it lives in
`Karaoke/Karaoke/Common/KaraokeTheme.swift` beside the existing `Palette`, `Space`, `Radius`
and `Hit` groups, except where stated.

---

## 1. TypeToken

A typographic role, expressed as data rather than as a `Font`.

It cannot be a `Font` constant. `@ScaledMetric` conforms to `DynamicProperty` and only resolves
inside a view, so a token that scales has to be resolved at the call site — see `research.md`
R5.

| Field | Type | Required | Constraint |
|---|---|---|---|
| `baseSize` | `CGFloat` | yes | **MUST be at least 13** at the default text size (FR-015) |
| `weight` | `Font.Weight` | yes | **MUST NOT be lighter than `.regular`** (FR-015) |
| `design` | `Font.Design` | no, defaults `.default` | `.monospaced` is permitted only for the timecode role |
| `relativeTo` | `Font.TextStyle` | yes | The Dynamic Type curve the role follows. Must match the curve of adjacent text, or an icon will grow at a different rate from the words beside it. |
| `maxDynamicTypeSize` | `DynamicTypeSize?` | no, defaults `nil` | When set, the role is clamped. **A clamped role MUST also offer `.accessibilityShowsLargeContentViewer()`** (FR-016, research R6). |

### Validation rules

- No token may declare `baseSize` below 13.
- No token may declare a weight lighter than `.regular`.
- A token with a non-nil `maxDynamicTypeSize` is only valid on fixed chrome or on a display
  role. It is invalid on scrollable reading content.

---

## 2. Theme.Typography — the named scale

Every piece of text and every SF Symbol in the app refers to one of these. No call site writes
a point size (FR-014).

### Text roles

| Token | Base | Weight | Curve | Clamp | Used for |
|---|---|---|---|---|---|
| `displayTitle` | 28 | `.bold` | `.title` | `.xxxLarge` | The now-playing song title on the player |
| `screenTitle` | 22 | `.bold` | `.title2` | — | Empty-state headlines, `SectionHeading` |
| `rowTitle` | 17 | `.semibold` | `.headline` | — | Song titles in search, queue, library, saved, suggestions |
| `body` | 17 | `.regular` | `.body` | — | Descriptions, settings rows, instructions |
| `bodyEmphasis` | 17 | `.semibold` | `.body` | — | Button labels, selected states |
| `secondary` | 15 | `.regular` | `.subheadline` | — | Channel names, supporting lines |
| `caption` | 13 | `.medium` | `.caption` | — | Durations, state badges, status pills |
| `timecode` | 17 | `.semibold` | `.body` | — | Elapsed and remaining time, dB values. `design: .monospaced` so digits do not jitter as they count. |

### Glyph roles

All seven of the hard-coded sizes in the app today are **SF Symbol sizes, not text sizes**.
They collapse into four roles.

| Token | Base | Weight | Curve | Clamp | Replaces |
|---|---|---|---|---|---|
| `glyphPrimary` | 30 | `.semibold` | `.title` | `.xxxLarge` | `PlayerView.swift:70` — play/pause |
| `glyphTransport` | 26 | `.semibold` | `.title2` | `.xxxLarge` | `PlayerView.swift:86` — seek buttons |
| `glyphStatus` | 32 | `.semibold` | `.title` | — | `PlaybackErrorView.swift:69` and `:148` — error icons |
| `glyphEmpty` | 44 | `.regular` | `.largeTitle` | — | `KaraokeTheme.swift:118`, `PlayerVideoStage.swift:34`, `SearchView.swift:162` |

### Two deliberate visual changes, called out so they are not mistaken for drift

1. **`.light` becomes `.regular`.** `KaraokeTheme.swift:118` and `PlayerVideoStage.swift:34`
   both specify `weight: .light` at 44 pt. FR-015 forbids any weight lighter than regular,
   because thin strokes disappear in a dim room. Those two glyphs get fractionally heavier.
2. **40 pt becomes 44 pt.** `SearchView.swift:162` uses 40 where two other empty states use 44.
   A separate token for a 4-point difference would not pay for itself (Principle VII), so the
   three unify on `glyphEmpty`.

### Counting rule

`glyphPrimary`, `glyphTransport` and the transport row generally are fixed chrome: they cannot
scroll, and FR-007 forbids them from taking height from the video when text grows. They are
therefore clamped, and each clamped control must carry
`.accessibilityShowsLargeContentViewer()` so a long press still reveals it at full
accessibility size.

Search results, queue, library, saved songs and settings are scrollable reading content. They
are **not** clamped.

---

## 3. Palette changes

Two colour tokens change. Everything else in `Theme.Palette` is kept.

| Token | Today | Becomes | Why |
|---|---|---|---|
| `contentIssue` | `rgb(0.95, 0.64, 0.22)` | `rgb(1.0, 0.42, 0.20)` | It is currently the same hue as `accent` — `rgb(1.0, 0.706, 0.251)` — so "this control is selected" and "something is wrong with this content" look alike. FR-021 requires them to differ in hue. The replacement is a red-orange sitting between the amber accent and the existing red. |
| `onAccent` | *(does not exist)* | `rgb(0.055, 0.055, 0.067)` | New. The label colour for text and glyphs placed on a filled accent control. White on amber measures about 1.9:1 and fails FR-023; this value, equal to `background`, measures about 10.9:1. |

`mechanismIssue` at `rgb(0.91, 0.33, 0.33)` is checked against the new `contentIssue` during
implementation. If the two read as the same colour, `mechanismIssue` moves to a cooler red
around `rgb(1.0, 0.27, 0.33)`.

Colour alone never carries a state (FR-022): every problem state keeps an icon or a text label
alongside it.

---

## 4. View state

None of this is persisted. It exists only while the player is on screen.

| Entity | Type | Lifetime | Notes |
|---|---|---|---|
| `isLandscape` | derived `Bool` | per layout pass | **Derived from `verticalSizeClass == .compact`, never from `UIDevice.current.orientation`** — see research R3. A device laid flat on a table reports `.faceUp`, which would throw the interface out of landscape mid-song. |
| `isToneExpanded` | `Bool` | while the player is on screen | Whether the inline tone panel is open. Replaces the `showEqualizer` sheet flag. Resets when the player is left. |
| `playerController` | `@Observable` reference | the life of the player host | Owns the single `AVPlayer`. Held with `@State` by a host view whose own identity does not change, so rotation cannot tear the player down — research R2. |

### State transitions — tone panel

```text
collapsed ──(tap Tone in the control area)──▶ expanded
expanded  ──(tap Tone again, or Done)───────▶ collapsed
expanded  ──(leave the player)──────────────▶ collapsed
```

Invariant across every transition: **the video remains wholly visible and undimmed** (FR-002).
Expanding the panel shrinks the fitted video slightly; it never overlays it.

### State transitions — orientation

```text
portrait  ──(device turned on its side)──▶ landscape
landscape ──(device turned upright)──────▶ portrait
```

Invariants: playback does not stop, restart, or lose position (FR-006); the single
`VideoPlayer` is never destroyed and never leaves structural index 0 of its container
(research R2).

---

## 5. Entities named in the specification

| Spec entity | Realised as |
|---|---|
| **Text role** | `TypeToken` plus an entry in `Theme.Typography` (sections 1 and 2) |
| **Width class** | Not modelled as stored state. Read from the environment at the point of use. This round reads the **vertical** size class for orientation; the horizontal size class belongs to the deferred Stories 4 and 5. |
| **Control area** | The fixed, non-scrolling region described in `contracts/player-layout.md`. Defined by reach, not by a measurement, so it has no numeric field here. |
| **Reading distance** | Not a runtime value. It is the rationale behind the base sizes in section 2 and the acceptance distances in `quickstart.md`. |
