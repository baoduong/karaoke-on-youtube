# Phase 0 Research: Professional iPhone and iPad Interface

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04

Scope for this round is the iPhone only. Stories 4 and 5 (iPad at a regular width) stay in
the specification and are not researched here.

---

## R1. Keeping the video unobscured while the tone control is open

### Correction to the specification's premise

FR-002 says the tone panel "slides up over" the video. Measured, that is **not what happens
in portrait**, and the plan must not be built on it.

On an iPhone 15 Pro (393 x 852 pt, 59 pt top safe area), a 16:9 video pinned below the safe
area occupies roughly y = 59 to y = 280 — the top third. A `.medium` detent sheet occupies
roughly y = 426 to the bottom. They do not overlap; there is about 146 pt of clearance.

The real portrait defects are different, and both are still real:

1. **The sheet dims the presenter.** Without `presentationBackgroundInteraction`, UIKit
   places a dimming view over everything behind the sheet. In a dim room, dimming the lyrics
   is the same failure as covering them, and it is the one that actually happens today.
2. **`.large` is an offered detent.** `EqualizerView.swift:50` declares
   `.presentationDetents([.medium, .large])`, so the singer can drag the sheet up over the
   video — by accident, mid-song, with wet hands on a phone.
3. **In landscape it covers outright.** When the video fills the screen, any sheet overlays
   the lower part of the picture, which is exactly where burned-in karaoke lyrics sit.

### Decision

**Present the tone control inline, as a panel that participates in layout, not as a sheet.**

### Rationale

A `.sheet` always overlays; it never resizes or pushes the presenting hierarchy. That is
architectural, not a configuration choice, so no combination of detents makes a sheet safe in
landscape. A panel that is part of the layout causes the video — fitted with
`contentMode: .fit` — to shrink slightly and stay **wholly visible** in both orientations.
Shrinking the picture a little is acceptable; hiding its lower edge is not, because that is
where the words are.

This also satisfies FR-010, which requires the tone control to be reachable from the lower
control area rather than only from the top toolbar.

### Alternatives considered

| Option | Portrait | Landscape | Rejected because |
|---|---|---|---|
| Keep `.sheet`, drop `.large`, add `presentationBackgroundInteraction(.enabled(upThrough: .medium))` | Video visible and undimmed | Overlays the picture | Fails landscape, which is the orientation the words most need |
| `.popover` + `.presentationCompactAdaptation(.popover)` | Video visible if anchored below it | Floating bubble still covers part of the picture | Same failure, and a floating bubble over video reads as unfinished |
| `.inspector` (iOS 17) | Adapts to a sheet on compact width | Same | Gives nothing a sheet does not |
| Inline panel in the layout | Video wholly visible | Video wholly visible | **Chosen** |

---

## R2. Changing orientation without interrupting playback

### Decision

**Keep exactly one `VideoPlayer` call site at a fixed structural position, and change only the
surrounding layout using `AnyLayout`. Own the `AVPlayer` in an `@Observable` object held by
`@State` on a view whose own identity never changes.**

### Rationale

`AVKit.VideoPlayer` is a `UIViewControllerRepresentable` over `AVPlayerViewController`. There
are two separate ways to break playback on rotation, and only the first is widely known:

1. **Recreating the `AVPlayer`.** Instantiating it inline, or holding it somewhere that is
   re-initialised when the view struct is re-evaluated, seeks the song back to zero.
2. **Destroying the view's structural identity.** This one bites even when the `AVPlayer`
   survives. Writing `if isLandscape { A } else { B }` compiles to `_ConditionalContent`, and
   switching branch tears down the `AVPlayerViewController` in one branch and builds a new one
   in the other — a black flash and an audio hiccup, mid-song, in front of the room.

`AnyLayout` solves the second: the subviews keep their identity while the container's axis
changes, so the player is never dismantled. This satisfies FR-006.

A trap worth naming: attaching `.onDisappear { player.pause() }` to the video makes a branch
switch pause the song.

### Alternatives considered

- **`.id()` to force identity across branches** — does not work. Identity is not merged across
  `_ConditionalContent` branches, and changing an `.id()` value forces a teardown, which is the
  opposite of what is wanted.
- **`@StateObject` with `ObservableObject`** — works, but `@Observable` plus `@State` is the
  iOS 17 idiom and avoids redraws when unrelated properties change. The project already
  targets iOS 17 and Swift 6.

---

## R3. Detecting orientation

### Decision

**Use `@Environment(\.verticalSizeClass) == .compact` to mean landscape. Never use
`UIDevice.current.orientation`.**

### Rationale

`UIDevice.current.orientation` reports `.faceUp` when the device is lying flat. A phone propped
on a table or laid down between verses would therefore snap the interface out of its landscape
layout in the middle of a song. The vertical size class reflects the interface orientation of
the window and is unaffected by the device being flat.

### Alternatives considered

- `GeometryReader` comparing width to height — correct, but heavier and it perturbs layout.
  Acceptable as a fallback where a size class is unavailable.
- `UIDevice.orientationDidChangeNotification` — same `.faceUp` flaw.

---

## R4. Making the video fill the screen in landscape

### Decision

**Release the 16:9 aspect constraint in landscape and let the single `VideoPlayer` fill the
window, with system chrome hidden.**

Modifiers that carry this, all current on iOS 17:

- `.aspectRatio(isLandscape ? nil : 16/9, contentMode: .fit)`
- `.ignoresSafeArea(edges: isLandscape ? .all : [])`
- `.toolbar(isLandscape ? .hidden : .visible, for: .navigationBar, .tabBar)`
- `.statusBarHidden(isLandscape)`
- `.persistentSystemOverlays(isLandscape ? .hidden : .automatic)`

### Rationale

`videoGravity` defaults to `.resizeAspect`, so a 16:9 picture on a 19.5:9 phone is letterboxed
rather than cropped. That matters here more than usual: cropping would cut the bottom of the
frame, which is where burned-in lyrics sit. `persistentSystemOverlays` hides the home
indicator, which otherwise sits over that same bottom edge.

This satisfies FR-004 and is the only means available to enlarge the words on a phone now that
a television is ruled out.

### Alternatives considered

- **`AVPlayerViewController`'s own full-screen button** — presents a separate modal window that
  fights custom overlays, and it is the system's control rather than ours. Rejected.
- **A dedicated full-screen route presented over the player** — a second presentation to keep in
  sync with playback state, for no gain over expanding in place.

### Open consequence, not resolved here

`AVKit.VideoPlayer` exposes no `showsPlaybackControls` parameter. Its native transport overlay
therefore appears on touch and includes a full-screen button that would conflict with the
layout above. Suppressing it requires a small `UIViewControllerRepresentable` around
`AVPlayerViewController`. Whether to do that is a task-level decision; it is recorded in
`contracts/player-layout.md` as a constraint rather than settled here.

---

## R5. A typographic scale that actually scales

### Decision

**Define typography as data — a token carrying base size, weight, design, the Dynamic Type
curve it follows, and an optional clamp — and resolve it to a `Font` inside a `ViewModifier`
using `@ScaledMetric(relativeTo:)` driving `Font.system(size:weight:design:)`.**

### Rationale

The central fact, and the reason the current code fails FR-016:

> **`Font.system(size:weight:design:)` does not scale with Dynamic Type.** It returns the raw
> point size. All seven hard-coded sizes in this app are therefore frozen, and no amount of
> the user enlarging system text affects them.

The obvious repairs are both wrong:

- **`Font.custom(name:size:relativeTo:)` does scale** — but it resolves a font by PostScript
  name through CoreText, and the San Francisco system font has no public PostScript name. It
  silently falls back to Helvetica. Unusable for a system-font app.
- **`UIFontMetrics(forTextStyle:).scaledFont(for:)` bridged via `Font(uiFont)`** is a late-
  binding trap. The bridge ignores the SwiftUI environment entirely, so the value is frozen at
  creation and ignores `.dynamicTypeSize(...)`, previews, and subtree clamping.

`@ScaledMetric(relativeTo:)` reads `@Environment(\.dynamicTypeSize)` and applies the same
non-linear curve Apple uses internally. Feeding its output into `Font.system(size:)` gives
explicit size and weight **and** correct scaling. It is the only combination that satisfies
FR-013, FR-014, FR-015 and FR-016 together.

Constraint that shapes the design: `@ScaledMetric` conforms to `DynamicProperty`, so it must
live inside a `View` or `ViewModifier`. Tokens therefore cannot be `static let Font` values —
they must be plain data resolved at the call site. This is why `data-model.md` describes a
token struct rather than a font constant.

### Alternatives considered

| Option | Rejected because |
|---|---|
| `static let x = Font.system(size: 30, weight: .bold)` | Does not scale. This is today's bug with nicer names. |
| `static let x = Font.system(.title2, weight: .bold)` | Scales correctly, but gives no control over point size, so the roles this app needs cannot be expressed. |
| `Font.custom("SFPro-Bold", size:relativeTo:)` | Falls back to Helvetica; San Francisco has no public PostScript name. |
| `Font(UIFontMetrics(...).scaledFont(for:))` | Ignores the SwiftUI environment; frozen at creation. |

---

## R6. Keeping large text from breaking the player

### Decision

**Clamp Dynamic Type only on fixed chrome and on display-sized roles, never on scrollable
reading content, and pair every clamp with `.accessibilityShowsLargeContentViewer()`.**

### Rationale

At `.accessibility5`, body text reaches about 53 pt. The player's fixed control row cannot
absorb that without pushing controls off screen or stealing height from the video — and
FR-007 forbids taking space from the video. Apple's own guidance accepts clamping for fixed
chrome that cannot scroll, on the explicit condition that a long-press large-content viewer is
offered instead, so the information is still reachable at accessibility sizes.

Search results, the queue, the library and settings are scrollable reading content and are
**not** clamped. They may grow freely; that is what scrolling is for.

### Alternatives considered

- **Clamp globally** — an accessibility regression, and unnecessary for scrollable content.
- **Clamp nothing** — violates FR-007 at large sizes, because something has to give and the
  only elastic element left is the video.

---

## R7. Switching layout when text gets very large

### Decision

**Use `AnyLayout` driven by `dynamicTypeSize.isAccessibilitySize` for rows whose horizontal
arrangement stops fitting, rather than `if/else` between two stacks.**

### Rationale

The same identity rule from R2 applies to ordinary rows: an `if/else` between `HStack` and
`VStack` destroys subview identity, losing state and animations. `AnyLayout` changes the axis
while keeping the children. Using one mechanism for both the player's orientation change and
rows' accessibility reflow keeps a single pattern in the codebase, which matters for
Principle VII.

`ViewThatFits(in: .horizontal)` is a reasonable alternative for rows where the trigger is
available width rather than text size; it is left as an implementation choice per row.

---

## Resolved unknowns

Every `NEEDS CLARIFICATION` from Technical Context is closed:

| Unknown | Resolved by |
|---|---|
| How to adjust tone without obscuring the video | R1 — inline panel, not a sheet |
| Whether rotation restarts playback, and how to prevent it | R2 — single `VideoPlayer`, `AnyLayout`, `@Observable` + `@State` |
| How to detect landscape safely for a device that gets laid flat | R3 — `verticalSizeClass`, never `UIDevice.orientation` |
| How to fill the screen in landscape without the system's full-screen control | R4 — expand in place, hide chrome |
| How to get custom point sizes that still honour Dynamic Type | R5 — `@ScaledMetric(relativeTo:)` into `Font.system(size:)` |
| Whether clamping large text is permissible | R6 — yes for fixed chrome and display roles, with a large-content viewer |
