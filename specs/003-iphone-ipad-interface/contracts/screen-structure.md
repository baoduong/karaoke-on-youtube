# Contract: Screen Structure

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04

Rules every screen obeys so the app reads as one product rather than several. These are the
structural counterparts to `typography.md`, which governs what text looks like; this one
governs how a screen is put together.

Scope is the iPhone.

---

## C-S1. One navigation container per screen — FR-019

A screen presented inside a navigation container **MUST NOT** introduce another one.

Exactly one navigation bar and one title are visible at any time.

Known breaches today, both of which show on iPhone and not only on iPad:

| Screen | Breach |
|---|---|
| `Features/Library/LibraryView.swift` | Pushed from the Library tab's `NavigationStack`, then wraps its own body in a second `NavigationStack` titled "Library" |
| `Features/Library/SavedSongsView.swift` | Reachable by two different pushes, and wraps its own body in a `NavigationStack` titled "Saved Songs" |

A view that needs to work both as a pushed destination and as a root **MUST** take the
container from its caller rather than providing its own.

**Verification**: open every screen and count navigation bars. One, every time.

## C-S2. One authoritative place per collection — FR-020

A collection of songs **MUST** be rendered in exactly one place.

The breach today: favourites appear inline on `LibraryView` *and* again on a pushed
`FavouritesDetailListView`, with nothing to tell a user which is the real one. One of the two
goes.

This also settles the navigation confusion around it — `SavedSongsView` is currently reachable
by two different routes, from the Library tab's list and from a card inside `LibraryView`.
After this contract there is one route to each collection.

**Verification**: count the places that render the favourites list. The number is one.

## C-S3. Every screen uses the shared visual language — FR-018

Every screen **MUST** draw its surfaces, colours, spacing, and corner radii from
`Theme`. No screen may fall back to system defaults for these.

Named breach: `Features/Settings/SigningValidityView.swift` uses a plain system `List` with raw
`.red`, `.orange`, `.green` and `.secondary`, and literal spacing values. It is the one screen
that looks like a different application.

**Verification**: place each screen beside any other. They belong to the same app.

## C-S4. Empty states are designed, not absent

A screen with nothing to show **MUST** present the shared empty state rather than a bare
surface. This applies to favourites, saved songs, the queue, and search before a query.

The shared `EmptyStateView` already exists and is already used in seven places; this contract
simply forbids new screens from skipping it.

**Verification**: empty every collection and visit each screen.

## C-S5. Long titles truncate, they do not reflow the row

A long song title **MUST** truncate predictably. It **MUST NOT** push controls off screen, and
**MUST NOT** change a row's height unpredictably.

Where a row cannot fit horizontally at large text sizes, the row changes axis via `AnyLayout`
rather than an `if`/`else` between two stacks, for the identity reason given in `research.md`
R7.

**Verification**: queue a song with a very long Vietnamese title and view it on every screen
that lists songs, at the default text size and at `.accessibility5`.

---

## Deferred with the iPad — FR-024

FR-024 requires that a label naming a device names the device the user is actually holding.
The two breaches are iPad-only in effect:

- `Features/Player/PlayerVideoStage.swift:94` and `:105` — hard-coded `"Phone speaker"` and the
  `iphone` symbol
- `Features/Settings/SigningValidityView.swift:78` and `:84` — "Open AltStore on your iPhone."

On an iPhone all four are correct. They become wrong only on a device this round does not
design for, so FR-024 moves to the deferred set with Stories 4 and 5 rather than being fixed
blind. It is recorded here so it is not lost.

Note that `SigningValidityView` is still rewritten this round under C-S3; the wording is simply
left as it is until the iPad work happens.
