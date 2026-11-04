# Feature Specification: Tone Control (Equalizer)

**Feature Branch**: `002-equalizer`

**Created**: 2026-11-03

**Status**: Implemented — specification written after the fact to close the gap

**Input**: User description: "một chức năng tiếp theo rất đáng tiền, đó là `Equalizer` (EQ), một số bài hát không được như mong đợi, nhưng với EQ tôi có thể chỉnh tăng 1 chút treble hoặc giảm 1 chút bass, cái này rất có ý nghĩa, không cần phải tinh chỉnh trên loa kéo mỗi lần."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fix a song that sounds wrong, without leaving the microphone (Priority: P1)

A singer is part-way through a karaoke track that sounds dull, or boomy, on
the PA speaker. Today the only remedy is to walk to the speaker and turn its
knobs — during the song, in front of the room, and then turn them back for the
next song. The singer wants to correct the sound from the phone already in
their hand.

**Why this priority**: This is the entire reason the feature exists. Without
it, nothing else here has value.

**Independent Test**: Start any song, open the tone control, raise treble and
lower bass, and confirm the sound from the PA changes accordingly while the
song keeps playing uninterrupted.

**Acceptance Scenarios**:

1. **Given** a song is playing, **When** the singer raises the treble,
   **Then** the sound through the PA becomes brighter within the time it takes
   to notice, with no gap, click, or stutter in the music.
2. **Given** a song is playing, **When** the singer lowers the bass,
   **Then** the low end is reduced and the song continues without interruption.
3. **Given** the singer has adjusted several bands, **When** they choose to
   return to flat, **Then** the sound returns to the untouched original.
4. **Given** the tone control has never been touched, **When** a song plays,
   **Then** the sound is exactly what the source provides, changed only by
   volume.

---

### User Story 2 - Set it once, not every song (Priority: P2)

The PA speaker and the room do not change between songs. A singer who has
found a setting that suits their equipment expects it to still be there for
the next song, and after closing and reopening the app.

**Why this priority**: Without persistence the feature is still usable but
becomes a chore — re-adjusting every song is the problem it set out to solve.

**Independent Test**: Adjust the tone, play a different song, confirm the
setting still applies; close the app, reopen it, confirm the setting survived.

**Acceptance Scenarios**:

1. **Given** the singer has adjusted the tone, **When** the next song starts,
   **Then** the same adjustment applies without being re-entered.
2. **Given** the singer has adjusted the tone, **When** the app is closed and
   reopened, **Then** the adjustment is still in effect.
3. **Given** the tone control is switched off, **When** the app is reopened,
   **Then** it is still off.

---

### User Story 3 - Know when it cannot be applied (Priority: P3)

Some songs may play through a path the system will not let the tone control
reach. The singer must be told, rather than moving a control that silently
does nothing.

**Why this priority**: It affects trust rather than capability. A control that
appears to work and does not is worse than one that admits its limits — but it
only matters on the subset of songs where the limit applies.

**Independent Test**: Play a song on a path the tone control cannot reach,
open the control, and confirm it states plainly that it is unavailable for
this song.

**Acceptance Scenarios**:

1. **Given** a song the tone control cannot be applied to, **When** the singer
   opens the control, **Then** it says so in terms describing their situation.
2. **Given** the control was unavailable for one song, **When** a song that
   accepts it starts, **Then** the control works and the singer's saved
   settings apply.

---

### Edge Cases

- **A large boost on already-loud material.** Raising a band on a track
  mastered near maximum level would distort. The system must prevent audible
  distortion rather than producing it.
- **Rapid adjustment.** Dragging a control produces a continuous stream of
  changes. The music must not click, stutter, or drop out while this happens.
- **Corrupted or hand-edited stored settings.** A stored value outside the
  allowed range must never reach the speaker. At party volume this is a
  hearing-safety and equipment-damage concern, not merely a wrong number.
- **Switching songs mid-adjustment.** A setting applied to one song must not
  arrive late and relabel or disturb a song the singer has since moved to.
- **Bypass must be exact.** With the control off, the output must be the
  source unchanged apart from volume — this is what keeps the project's
  existing no-processing guarantee verifiable.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST let the singer adjust the tone of the backing track
  across a low, a middle, and a high frequency band.
- **FR-002**: System MUST apply an adjustment to the song currently playing,
  without stopping, restarting, or interrupting it.
- **FR-003**: System MUST default to no adjustment, and MUST let the singer
  switch the whole control off independently of the band positions.
- **FR-004**: System MUST return every band to neutral on a single action.
- **FR-005**: System MUST confine every adjustment to a bounded range, and
  MUST reject or clamp any value outside it, whether entered by the singer or
  read back from storage.
- **FR-006**: System MUST retain the singer's tone settings across songs and
  across app restarts.
- **FR-007**: System MUST NOT alter the pitch or tempo of the backing track.
  Shaping frequency response is the only permitted change.
- **FR-008**: System MUST NOT apply any adjustment the singer did not ask for.
  No automatic correction, levelling, or enhancement.
- **FR-009**: System MUST prevent an adjustment from producing audible
  distortion on material that is already near maximum level.
- **FR-010**: System MUST tell the singer when the tone control cannot be
  applied to the song currently playing, rather than presenting a control that
  has no effect.
- **FR-011**: System MUST keep the singer's settings when the control is
  unavailable for one song, and apply them to the next song that accepts them.
- **FR-012**: System MUST make the tone control reachable from the screen the
  singer is on while a song is playing.

### Key Entities

- **Tone Setting**: The singer's chosen adjustment. Holds one value per
  frequency band plus a single on/off state. Bounded on every value. One
  setting applies to everything that plays; it is not stored per song.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A tone adjustment is audible through the PA speaker within
  200 milliseconds of the singer making it, with no click, gap, or dropout.
- **SC-002**: With the tone control off or neutral, the sound is identical to
  the untouched source apart from volume, confirmed by recording the output
  and comparing it.
- **SC-003**: A singer can find the control, change the sound, and return to
  the song in under 15 seconds, without stopping playback.
- **SC-004**: Tone settings survive at least ten consecutive app restarts
  unchanged.
- **SC-005**: No adjustment at any combination of band positions produces
  audible distortion on a track mastered near maximum level.
- **SC-006**: A two-hour session with the tone control active completes with
  no audio dropout and no unbounded growth in memory.
- **SC-007**: On every song where the control cannot be applied, the singer is
  told; the count of songs where the control appears functional but does
  nothing is zero.
- **SC-008**: No value outside the permitted range ever reaches the speaker,
  including values injected directly into storage. Verified by writing
  out-of-range values and confirming the applied result stays within bounds.

## Assumptions

- **Three bands are enough.** The stated need is "a bit more treble, a bit
  less bass". A finer control would serve that no better while giving a singer
  holding a microphone more to get wrong mid-party. Revisit only if three
  prove insufficient in use.
- **One setting for everything, not one per song.** The PA and the room are
  what the setting compensates for, and those do not change between songs.
  Per-song memory is deliberately deferred until re-adjusting proves annoying
  in practice.
- **The singer adjusts by ear, during a song.** There is no reference tone, no
  analyser, and no preset library. The feedback loop is the room.
- **Level may be traded for headroom.** Preventing distortion by reducing
  overall level is acceptable; the PA has its own volume control. Changing the
  dynamics of the material is not acceptable.
- **Relationship to feature 001.** The parent specification carries FR-043 and
  SC-015 for this same obligation, added when the no-processing rule was
  amended to permit it. This specification is the authority; those two entries
  should be reduced to cross-references so the requirement is stated once.
  Tracked as convergence work rather than changed here, because this command
  does not edit feature 001.
- **Governing constraints inherited from the project constitution.** The
  real-time audio path rules apply in full; any claim about audio behaviour
  counts only when measured on physical hardware; and settings stay on the
  device.
