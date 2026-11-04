# Contract: Player Layout

**Feature**: `003-iphone-ipad-interface` | **Date**: 2026-11-04

Rules the player screen must obey. They exist because, with no television, **the video is the
lyrics**: anything that covers, dims, or shrinks it takes words away from someone who is
mid-line in front of an audience.

Scope is the iPhone. The regular-width layout of Stories 4 and 5 is deferred.

---

## C-P1. The video is never obscured

While a song is playing, **no** element may overlap, dim, or otherwise obscure any part of the
video. This holds in both orientations and while any control is being adjusted.

Consequences, all binding:

- The tone control **MUST NOT** be presented as a `.sheet`, a `.popover`, or a
  `.fullScreenCover`. A sheet always overlays the presenter and dims it; that is architectural
  and no detent configuration avoids it. See `research.md` R1.
- The tone control **MUST** be an inline panel that participates in layout, so that opening it
  shrinks the fitted video rather than covering it.
- The audio-quality detail is under the same rule while a song plays.

**Verification**: capture the player with the tone panel open, in both orientations, and
confirm the full 16:9 frame is visible and undimmed. The capture is scripted — see
`quickstart.md`.

## C-P2. The video is the largest element

At every width and in both orientations, the video occupies more of the screen than any other
element.

**Verification**: by eye against a capture, on a physical device.

## C-P3. The video does not scroll away

The video is pinned. Scrolling anything below it **MUST NOT** move it off screen.

This is already true today and must survive the restructuring — `PlayerVideoStage.swift:8`
records why it was done in the first place.

## C-P4. Landscape fills the screen

When `verticalSizeClass == .compact`, the video **MUST** expand to fill the window and system
chrome **MUST** be hidden: navigation bar, tab bar, status bar, and the home indicator.

The 16:9 picture **MUST** be fitted, never cropped. Cropping removes the bottom of the frame,
which is where burned-in lyrics sit.

**Verification**: on a physical phone, in landscape, the displayed video area is larger than in
portrait and no part of the frame is cut off.

## C-P5. Orientation is read from the size class

Landscape **MUST** be determined by `verticalSizeClass == .compact`.

`UIDevice.current.orientation` **MUST NOT** be used. It reports `.faceUp` when the device is
lying flat, which would throw the interface out of its landscape layout when a singer rests the
phone on a table between verses.

**Verification**: lay the phone flat, face up, while a song plays in landscape. The layout does
not change.

## C-P6. The player survives rotation

Rotating the device **MUST NOT** stop playback, restart the song, lose the playback position,
or show a black frame.

To make that achievable:

- There **MUST** be exactly one `VideoPlayer` call site on the player screen.
- It **MUST NOT** appear inside any branch of an `if`/`else` or `switch`. Branches compile to
  `_ConditionalContent`, and switching branch dismantles the underlying view controller.
- Layout changes **MUST** be expressed by swapping the container via `AnyLayout`, keeping the
  video at the same structural position.
- The `AVPlayer` **MUST** be owned by an `@Observable` object held in `@State` by a host whose
  own identity does not change.
- `.onDisappear { player.pause() }` **MUST NOT** be attached to the video.

**Verification**: rotate repeatedly during playback on a physical device; the position
continues uninterrupted and the audio does not break.

## C-P7. The control area

Everything the singer needs mid-song **MUST** sit in a fixed, non-scrolling region in the lower
portion of the screen, reachable by the thumb of the hand holding the phone.

That set is exactly: play/pause, seek backward, seek forward, next queued song, and the tone
control.

Rules:

- The control area **MUST NOT** scroll.
- The tone control **MUST NOT** be reachable only from the top navigation bar.
- Content not needed mid-song **MUST NOT** occupy the control area. Suggestions move out of it.
- Each control keeps a hit target of at least `Theme.Hit.minimum` (44 pt).

**Verification**: hold the phone in one hand with the other hand occupied and operate every
control without changing grip. A person, a real microphone, a physical device.

## C-P8. Larger text never costs the video

When the system text size grows, any space the layout must surrender **MUST** come from
something other than the video.

This is why the control area's roles are clamped — see `contracts/typography.md` C-T5.

**Verification**: at `.accessibility5`, the video's displayed area is no smaller than at the
default setting.

---

## Known constraint, deliberately unresolved

`AVKit.VideoPlayer` exposes no way to hide its native transport overlay, which appears on touch
and carries a full-screen button that fights C-P4. Suppressing it requires wrapping
`AVPlayerViewController` in a small `UIViewControllerRepresentable` with
`showsPlaybackControls = false`.

Whether to do that is left to implementation. If the native overlay is kept, C-P1 is judged
against the resting state rather than against a transient system overlay the user summoned.
This is recorded so the decision is made knowingly rather than discovered late.
