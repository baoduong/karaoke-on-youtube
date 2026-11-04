# Contract: Typography

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04

The interface this feature exposes is a user interface, so its contracts are the rules a screen
must obey to be considered part of this app. This one governs text and symbols. It is binding
on every view in the target.

---

## C-T1. One source of sizes

Every `Text` and every `Image(systemName:)` in the app **MUST** take its size and weight from a
role in `Theme.Typography`.

A call site **MUST NOT** write any of the following:

- `.font(.system(size: <number>...))`
- `.font(.custom(<name>, size: <number>))`
- `.font(Font(<a UIFont>))`
- a bare system text style such as `.font(.headline)` or `.font(.body)`

The last one is included on purpose. Bare text styles scale correctly but give no control over
size or weight, so a codebase mixing them with tokens has two competing scales and no way to
tell which is authoritative.

**Verification**: mechanical. A test fails the build if any of those four forms appears in
`Karaoke/Karaoke/**/*.swift`, with exactly one exemption: the body of the typography resolver
in `KaraokeTheme.swift`, which must call `Font.system(size:weight:design:)` because that is how
a `@ScaledMetric`-supplied size becomes a `Font`.

The exemption is the **resolver**, not the file. Scoping it to the whole of
`KaraokeTheme.swift` would silently excuse the shared components defined there — `EmptyStateView`
today carries a raw `.font(.system(size: 44, weight: .light))`, which is a real violation and is
task T031. A file-level exemption would hide it.

This is the one automated test this feature adds, and it exists because this is the only part
that can rot silently — see Principle IV.

## C-T2. Roles resolve through the environment

A role **MUST** be resolved to a `Font` inside a `View` or `ViewModifier`, driven by
`@ScaledMetric(relativeTo:)` feeding `Font.system(size:weight:design:)`.

A role **MUST NOT** be exposed as a `static let` of type `Font`.

Reason, established in `research.md` R5: `Font.system(size:)` does not scale with Dynamic Type,
`Font.custom` cannot address the San Francisco system font, and `UIFontMetrics` bridged through
`Font(_:)` ignores the SwiftUI environment. Only the `@ScaledMetric` route honours
`.dynamicTypeSize(...)`, previews, and subtree clamping.

**Verification**: reading the definition once. There is one resolution path; it is either
written this way or it is not.

## C-T3. The floor

No role renders below **13 points** at the default text size, and no role uses a weight lighter
than **`.regular`**.

**Verification**: mechanical, from the token table — every `baseSize >= 13` and every `weight`
at or above `.regular`.

## C-T4. Curves must match their neighbours

A role's `relativeTo` curve **MUST** match the curve of the text it sits beside.

Apple's curves are not linear with respect to one another: at `.accessibility5`, `.caption2`
grows by roughly 4.8x while `.largeTitle` grows by roughly 1.76x. An icon declared against
`.body` next to a title declared against `.title` will overtake the title as text grows, and
the row will look broken only at large sizes — which is exactly when nobody is looking.

**Verification**: on a physical device at `.accessibility3` and above, each row keeps its
intended visual hierarchy.

## C-T5. Clamping is permitted only where it is earned

A role **MAY** declare `maxDynamicTypeSize` only if it is fixed chrome that cannot scroll, or a
display-sized role that is already large.

Any clamped control **MUST** also carry `.accessibilityShowsLargeContentViewer()`.

Scrollable reading content — search results, queue, library, saved songs, settings —
**MUST NOT** be clamped.

**Verification**: on a physical device at `.accessibility5`, every clamped control reveals its
label under a long press, and every scrollable list is at full size.

## C-T6. Contrast

Text and glyphs **MUST** measure at least **4.5:1** against the surface behind them.

Content placed on a filled accent control **MUST** use `Theme.Palette.onAccent`. White on the
amber accent measures about 1.9:1 and is forbidden.

**Verification**: measured, per colour pair, not estimated.

## C-T7. Colour never carries a state alone

Every state that is communicated with colour **MUST** also carry an icon or a text label.

The accent colour and the content-problem colour **MUST** differ in hue, not only in
lightness.

**Verification**: on a physical device with the display set to greyscale, every state remains
distinguishable.

---

## Applies to

Every view in `Karaoke/Karaoke/`, with no exception. `SigningValidityView.swift` is named
specifically because it presently uses the system `List` with raw `.red`, `.orange`, `.green`
and `.secondary`, and is the one screen that looks like a different app.
