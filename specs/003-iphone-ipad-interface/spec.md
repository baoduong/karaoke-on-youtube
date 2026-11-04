# Feature Specification: Professional iPhone and iPad Interface

**Feature Branch**: `003-iphone-ipad-interface`

**Created**: 2026-11-04

**Status**: Draft

**Input**: User description: "Improve the interface. I want a professional UI for iPhone and iPad. iPhone first; if the iPad cannot be served by the same UI, it may have its own." Clarified during drafting: no television is used, on any device.

## User Scenarios & Testing *(mandatory)*

The app is used in a dim living room. **There is no television.** The device itself is the
screen the singers look at, and the karaoke video carries its lyrics burned into the picture,
so the video *is* the lyrics. Sound goes to a separate speaker. One person sings with a
microphone in one hand and the device in the other, or with the device propped up in front of
them. Other people are waiting their turn. Everything below is written for that room.

This single fact — no television — governs the whole feature. Screen area spent on anything
other than the video is screen area taken away from the words the singer is reading.

### User Story 1 - Read the words while singing (Priority: P1)

A singer starts a song and immediately needs to read the lyrics off the device, continuously,
for four to five minutes, in a dim room, at whatever distance the device happens to be. Today
the video is one band in a vertical stack: it is capped to a phone-sized column even on a
large display, it keeps the same modest size when the device is turned on its side, and
opening the tone control slides a panel up over it. Every one of those takes words away from
someone who is mid-line.

**Why this priority**: Without a television, this is the app's one job. A singer who cannot
read the next line stops singing, and everyone in the room sees it. Controls, consistency and
layout all matter less than the words being legible, because the song fails without them.

**Independent Test**: Start a song and sing it through without touching anything. Then,
mid-song, open the tone control. The story passes only if the words remain readable at the
distance the device is actually used from, in both orientations, and if nothing at any point
covers the picture.

**Acceptance Scenarios**:

1. **Given** a song is playing, **When** the singer looks at the screen, **Then** the video is
   the largest element on it, and no decoration, control, or panel overlaps the picture.
2. **Given** a song is playing, **When** the singer opens the tone control, **Then** the video
   remains visible and unobscured while they adjust it.
3. **Given** a song is playing in portrait, **When** the device is turned on its side,
   **Then** the video grows to use the wider display rather than keeping its portrait size,
   and playback continues without interruption or restart.
4. **Given** a song is playing, **When** the singer scrolls whatever sits below the video,
   **Then** the video does not scroll away.
5. **Given** a song is playing on a display wider than a phone, **When** the singer looks at
   the screen, **Then** the video has grown to suit that display rather than being held to a
   phone-sized column.

---

### User Story 2 - Work the song one-handed, microphone in the other hand (Priority: P2)

A singer needs to adjust the tone, nudge the playback, or abandon a song that turned out to be
the wrong version — while holding a microphone and facing an audience. Today the tone control
sits in the toolbar at the top of the screen, the transport can be scrolled out of sight by
the list beneath it, and there is no way to move to the next queued song from the player at
all.

**Why this priority**: Failure here interrupts a performance in front of people. It ranks
below Story 1 only because a singer who cannot reach a control can still finish the song,
whereas a singer who cannot read the words cannot.

**Independent Test**: Hold the device in one hand, thumb only, as if the other hand holds a
microphone. Start a song. Without changing grip and without a second hand, reach every control
needed mid-song. If any requires a grip change, a second hand, or a scroll, the story fails.

**Acceptance Scenarios**:

1. **Given** a song is playing, **When** the singer reaches for the tone control one-handed,
   **Then** it is reachable in the lower portion of the screen without changing grip.
2. **Given** a song is playing and the content below the video is scrolled, **When** the singer
   looks for play/pause, **Then** the transport is still in the same place on screen.
3. **Given** a song turns out to be the wrong version, **When** the singer wants to move to the
   next queued song, **Then** a control to do that sits in the same reachable area as the
   transport.
4. **Given** the singer's hand covers the lower third of the screen, **When** they operate a
   mid-song control, **Then** the control is not hidden under their own hand.

---

### User Story 3 - A guest who has never used the app can read and work it in a dim room (Priority: P3)

At a party the device is passed to someone who has never seen the app. They need to find a
song, read its title at arm's length in low light, and understand what the screen is telling
them. Today text sizes are chosen per screen rather than from a shared scale, one screen
ignores the app's visual language entirely, two screens show doubled navigation bars, and the
favourites list appears twice with no way to tell which is authoritative.

**Why this priority**: It does not interrupt a performance, so it ranks below the two stories
that do. But it is the whole of what the owner asked for by "professional", and the passing of
the device between guests is the normal way this app is used.

**Independent Test**: Walk every screen in order. Check that text roles are consistent between
screens, that no screen looks like it came from a different app, that no screen shows two
navigation bars, and that each piece of information appears in exactly one authoritative place.

**Acceptance Scenarios**:

1. **Given** any screen, **When** its text is compared with the same role on another screen,
   **Then** size and weight match, because both come from one named scale.
2. **Given** the signing-validity screen, **When** it is placed beside any other screen,
   **Then** it uses the same surfaces, colours, and spacing as the rest of the app.
3. **Given** the Library or Saved-songs screen, **When** the user looks at the top of it,
   **Then** exactly one navigation bar and one title are shown.
4. **Given** a label or instruction that names a device, **When** it is read on an iPad,
   **Then** it names the device the user is actually holding.
5. **Given** an active control and an element reporting a problem are both on screen, **When**
   the user looks at them, **Then** they differ by more than colour alone and are not the same
   colour.

---

### User Story 4 - The iPad is a bigger screen to sing from (Priority: P4)

Someone props the iPad up on a table or a stand and people sing from it, exactly as they would
from a phone but further away and with more room. The iPad's whole advantage is that the words
can be larger. Today it squanders that: the video is capped at a phone-sized column with black
margins either side, and seven screens have no width treatment at all and stretch edge to edge.

**Why this priority**: The owner asked for iPhone first, and the iPhone stories deliver to a
singer using the app alone. This story is where the iPad stops being a phone layout and starts
earning its screen.

**Independent Test**: Prop an iPad at full width and sing a song from it from about two metres
away. The story passes if the words are comfortably readable at that distance and the video is
using the display rather than a centred column of it.

**Acceptance Scenarios**:

1. **Given** an iPad at full width with a song playing, **When** a singer looks at it from
   across a room, **Then** the video has grown to use the display and the words are readable
   at that distance.
2. **Given** an iPad at full width, **When** the user queues another song during playback,
   **Then** the playing video stays visible and legible throughout and is not replaced.
3. **Given** an iPad narrowed to a compact width, such as in a split-screen arrangement,
   **When** the user looks at the player, **Then** the single-column layout is shown, because
   the layout follows available width rather than the model of the device.
4. **Given** the available width changes while a song plays, **When** the layout changes,
   **Then** playback continues without interruption, restart, or loss of position.

---

### User Story 5 - Reach both ends of a list on the iPad without sweeping across it (Priority: P5)

Between songs people browse the queue, favourites, and saved songs. On an iPad at full width
those rows run the whole width of the display, so a song title sits at the far left and its
controls at the far right, an arm's sweep apart. The Library additionally buries its
collections behind pushes that a wide display has no need for.

**Why this priority**: It affects comfort rather than capability, and it happens between songs
rather than during one. Everything is reachable today, just awkwardly.

**Independent Test**: On an iPad at full width, open the Queue and the Library. Each row's text
and controls should be taken in and operated without moving a hand across the display, and
moving between Library collections should need no push-and-back cycle.

**Acceptance Scenarios**:

1. **Given** an iPad at full width showing the queue, **When** the user reads a row, **Then**
   that row's title and its controls are within one comfortable reach of each other.
2. **Given** an iPad at full width showing the Library, **When** the user switches collection,
   **Then** the list of collections stays visible and no back navigation is required.

---

### Edge Cases

- What happens when the device is turned on its side mid-song? The video must grow to suit the
  new orientation, and playback must not stop, restart, or lose its position.
- What happens on an iPad in a narrow split-screen arrangement? The compact layout is shown,
  and it must be complete — not a wide layout with pieces missing.
- What happens when the singer's text-size setting is at its largest? Every control must stay
  reachable and no label may be clipped — but the video must not be shrunk to make room for
  larger text, because the video is the thing being read.
- What happens when a song title is very long? It must truncate predictably rather than push
  controls off screen or change a row's height unpredictably.
- What happens when a screen has nothing to show — no favourites, no saved songs, an empty
  queue? The empty state must use the shared visual language rather than a bare screen.
- What happens when the tone control cannot be applied to the current song? The interface must
  say so rather than offering a control that silently does nothing.

## Requirements *(mandatory)*

### Functional Requirements

**The words stay readable (Story 1)**

- **FR-001**: The video MUST be the largest element on the player screen at every available
  width and in every orientation, because it carries the lyrics.
- **FR-002**: Nothing MUST overlap or obscure the video while a song is playing. This includes
  panels presented for the tone control and for audio quality, which today slide up over it.
- **FR-003**: The video MUST NOT scroll out of view when content below it is scrolled.
- **FR-004**: When the device is turned on its side, the video MUST grow to use the wider
  display rather than retaining its portrait proportions.
- **FR-005**: At a regular width, the video MUST grow to suit the display rather than being
  held to a phone-sized column.
- **FR-006**: A change of orientation or of available width MUST NOT interrupt playback,
  restart the song, or lose the playback position.
- **FR-007**: When larger system text sizes force a layout to give up space, that space MUST
  NOT be taken from the video.

**Reachability during a song (Story 2)**

- **FR-008**: Every control the singer needs while a song plays MUST sit in the lower portion
  of the screen, reachable by the thumb of the hand holding the device. That set is:
  play/pause, seek backward, seek forward, move to the next queued song, and the tone control.
- **FR-009**: The transport MUST hold a fixed position on screen and MUST NOT scroll out of
  view.
- **FR-010**: The tone control MUST be reachable from the player's lower control area and MUST
  NOT be reachable only from the navigation bar at the top of the screen.
- **FR-011**: Users MUST be able to move to the next queued song from the player's control
  area. The queue already advances by itself when a song finishes; this adds a deliberate way
  to do it early.
- **FR-012**: Content not needed mid-song MUST NOT occupy the reachable control area.

**One visual language (Story 3)**

- **FR-013**: The app MUST define a named typographic scale covering every text role it uses,
  and every piece of text MUST take its size and weight from that scale.
- **FR-014**: No text size or weight may be specified where the text is written. The seven
  existing hard-coded text sizes MUST be replaced by scale roles.
- **FR-015**: No text role may render below 13 points at the default text-size setting, and no
  role may use a weight lighter than regular, because thin small text is unreadable in a dim
  room.
- **FR-016**: Text MUST respond to the system text-size setting.
- **FR-017**: At a regular width, text roles MUST render larger than at a compact width,
  because the device is viewed from further away.
- **FR-018**: Every screen MUST use the app's shared surfaces, colours, spacing, and corner
  radii. The signing-validity screen, which uses system defaults today, MUST be brought onto
  them.
- **FR-019**: A screen pushed inside a navigation container MUST NOT introduce a second one,
  so exactly one navigation bar and one title are shown.
- **FR-020**: Any collection of songs MUST be presented in exactly one authoritative place. The
  favourites list, rendered today both inline and on a separate pushed screen, MUST appear once.
- **FR-021**: The colour marking a selected or active control MUST be visibly distinct in hue
  from the colour marking a content problem.
- **FR-022**: A state MUST NOT be carried by colour alone. Every problem state MUST also carry
  an icon or a text label.
- **FR-023**: Text and glyphs MUST meet a contrast ratio of at least 4.5:1 against the surface
  behind them, including text on filled accent-coloured controls.
- **FR-024**: Labels, instructions, and icons that name a device MUST name the device the user
  is holding. The hard-coded phone wording and phone icon shown today on iPad MUST be corrected.

**The iPad earns its screen (Stories 4 and 5)**

- **FR-025**: The interface MUST choose its layout from the width available to it, not from the
  device model. An iPad in a narrow arrangement MUST receive the compact layout.
- **FR-026**: At a regular width, queueing another song MUST NOT replace the playing video or
  reduce it below the size at which its words stay readable from across a room.
- **FR-027**: Screens holding a single list or a short form MUST be constrained to a readable
  measure and centred at a regular width. For those screens that is the finished iPad design,
  not a stopgap. This covers settings, signing validity, audio quality, and suggestions.
- **FR-028**: At a regular width, a list row's text and its controls MUST be grouped within one
  comfortable reach of each other rather than pushed to opposite edges.
- **FR-029**: At a regular width, the Library's collections MUST stay visible while a
  collection's contents are shown, so switching collection needs no back navigation.

### Key Entities

- **Text role**: A named entry in the typographic scale. Carries a size for compact width, a
  larger size for regular width, and a weight. Every piece of text refers to one.
- **Width class**: Whether the space available to the interface is compact or regular. A
  property of the window, not of the device, and it may change while the app runs.
- **Control area**: The fixed region of the player holding everything the singer needs
  mid-song. Defined by reachability, not by a fixed measurement.
- **Reading distance**: How far the singer's eyes are from the screen — about an arm's length
  for a handheld phone, about two metres for a propped iPad. Type sizes and the video's size
  are judged against it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A singer can sing a complete song, start to finish, reading only the device, at
  the distance that device is actually used from, without leaning in or squinting. Verified on
  a physical phone and a physical iPad by someone actually singing.
- **SC-002**: While a song plays, no interface element overlaps the video at any time,
  including while the tone control is open and being adjusted. Checked on a physical device.
- **SC-003**: Turning the device on its side mid-song increases the video's displayed area and
  causes no interruption, restart, or loss of position. Measured on a physical device.
- **SC-004**: On an iPad at full width, the video's displayed area is at least double what the
  current phone-width cap allows. Measured.
- **SC-005**: A singer holding the device one-handed, with the other hand occupied, reaches
  every mid-song control without changing grip. Verified on a physical phone by a person
  holding an actual microphone.
- **SC-006**: With the content below the video scrolled to its end, the transport is still
  visible and operable. Verified on a physical device.
- **SC-007**: Zero text sizes and zero text weights are specified at the point of use; every
  one comes from the named scale. Counted mechanically; the count today is seven.
- **SC-008**: Every screen renders at the largest system text size with no clipped label, no
  overflowing text, and no control pushed off screen — and with the video no smaller than at
  the default setting. Checked on every screen.
- **SC-009**: Every text and glyph colour meets or exceeds 4.5:1 contrast against the surface
  behind it. Measured, including text on filled accent controls, where today's combination
  measures approximately 1.9:1 and fails.
- **SC-010**: No screen shows more than one navigation bar or more than one title, and the
  number of places rendering the favourites list falls from two to one. Checked on every screen.
- **SC-011**: On an iPad at full width, a person queues a song during playback without the
  playing video being replaced or shrunk below readable size. Timed: under 20 seconds from
  picking the device up to the song being queued.
- **SC-012**: On an iPad at full width, no list row places its text and its controls more than
  one comfortable reach apart. Checked on every screen that shows a list.
- **SC-013**: A person who has not used the app before finds and starts a specific song in a
  dim room within 60 seconds, without being shown how.
- **SC-014**: Every screen is reachable from a running app and every control on it responds to
  input. Checked by operating each one, not by reading the code.

## Assumptions

- **No television is used, on any device.** The owner confirmed this during drafting. The
  device is the screen the singers read from, and the karaoke video carries its lyrics in the
  picture, which the code already relies on. Every requirement about screen area follows from
  this.
- Sound reaches the room through a separate speaker rather than the device, so the device's
  position is chosen for sight rather than for hearing. Nothing in this feature changes how
  audio is routed.
- The iPad is propped up and sung from, in the same way as a phone but further away. It is not
  treated as a control surface for a separate display, because there is no separate display.
- Landscape is already permitted on both device classes but no layout is written for it. This
  feature treats turning the device sideways as a supported way to make the words bigger,
  which is the only means available on a phone once a television is ruled out.
- The owner's "iPhone first" instruction is priority ordering, not exclusion. The iPad stories
  are in scope but ranked after the iPhone ones, and the iPad stays in breach of the
  constitution's Principle VIII until Stories 4 and 5 land. That intermediate state is accepted
  deliberately rather than overlooked.
- The existing dark palette, the amber accent, the spacing scale, the corner-radius scale and
  the tab structure are kept. The accent measures about 10.9:1 against the background and is a
  deliberate choice rather than a default, so only its collision with the content-problem
  colour is corrected.
- The interface stays locked to dark. A dim room is the only room this app is used in.
- No pitch or key transposition is in scope. The audio pipeline excludes pitch and tempo
  processing by design, and a key control would require a real-time render thread the app does
  not have and does not want.
- Moving to the next queued song surfaces an existing capability rather than adding a feature:
  the queue service already advances when a song finishes.
- The concept mockups held outside this repository are superseded. They predate the design
  system, show a lyrics layer that was later removed, omit the tone control that was later
  added, and are excluded by `.gitignore` as low-resolution reference. Nothing here derives
  from them.
- Reachability, legibility, and layout are verified by operating the app on physical devices,
  not by automated test, in keeping with the project's existing practice.
