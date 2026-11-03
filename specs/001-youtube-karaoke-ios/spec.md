# Feature Specification: YouTube-Sourced Karaoke App for iPhone/iPad

**Feature Branch**: `001-youtube-karaoke-ios`

**Created**: 2026-11-03

**Status**: Draft

**Input**: User description: "Xây dựng ứng dụng trên iphone/ipad để hát karaoke lấy nguồn nhạc karaoke từ youtube, chất lượng âm thanh cao nhất, không quảng cáo, không sử dụng app youtube có sẳn."

**Distribution decision (confirmed with user)**: Personal sideload (AltStore / Xcode direct install). This app is **not** intended for App Store distribution. See *Assumptions* and *Legal & Operational Risk* below.

**Scope decision (confirmed with user)**: The app is a **playback-only** device. The singer sings into a portable PA speaker ("loa kéo") connected over **Bluetooth**, which handles the microphone, vocal effects, and vocal/music mixing in its own hardware. The app therefore does **no** microphone capture, no live vocal monitoring, no vocal effects, and **no pitch or tempo processing**. Its entire job is to deliver the best available backing track to that speaker, ad-free, with the words on screen and a useful suggestion of what to sing next. See *Assumptions*.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find and play a karaoke track (Priority: P1)

The singer opens the app, types a song title, picks a karaoke version from the results, and the backing track starts playing through the connected PA speaker at the best audio quality the source offers. No advertisement interrupts the performance.

**Why this priority**: This is the entire product. Without search → play, nothing else has value. It is the smallest slice that is independently useful.

**Independent Test**: Install the app on a device, connect the PA speaker, search a known karaoke title, tap the first result, confirm audio plays through the speaker within the stated time budget at the expected quality, and confirm no ad plays before, during, or after.

**Acceptance Scenarios**:

1. **Given** the app is open and the device has network access, **When** the singer enters a search term and submits, **Then** a result list of candidate karaoke sources appears showing title, channel, and duration.
2. **Given** a result list is displayed, **When** the singer selects an item, **Then** the backing track begins audible playback and no advertisement is presented at any point.
3. **Given** the singer selected a source, **When** multiple audio renditions exist for that source, **Then** the system selects the highest-quality available audio rendition without asking the singer.
4. **Given** a backing track is playing, **When** the singer pauses and resumes, **Then** playback resumes from the same position.
5. **Given** a PA speaker is connected by cable or wirelessly, **When** a track plays, **Then** the audio is routed to that speaker and the app reports which route is in use.

---

### User Story 2 - Know what to sing next (Priority: P2)

A song ends and nobody knows what to put on. The singer wants the app to offer a handful of sensible next songs — the way the source platform does — so the party keeps moving without someone hunting through a search box between every number.

**Why this priority**: This is the difference between a search tool and a karaoke machine. Searching for every single song kills the momentum of an evening, and it is also what burns the search quota. Independent of P1, which ships and works without it.

**Independent Test**: Play a song to the end and confirm a list of suggested next songs appears, that the suggestions are plausibly related to what was just sung, and that adding one to the queue works. Separately, confirm suggestions still appear for a song with no upstream relation data, drawn from the singer's own history.

**Acceptance Scenarios**:

1. **Given** a song is playing or has just ended, **When** the singer looks at the suggestions, **Then** a list of candidate next songs is shown with title, channel, and duration.
2. **Given** suggestions are shown, **When** the singer picks one, **Then** it is added to the queue or starts playing, exactly as a search result would.
3. **Given** the upstream provides no relation data for the current song, **When** suggestions are requested, **Then** the app still offers candidates derived from the singer's own history and favourites rather than showing an empty list.
4. **Given** the singer has sung several songs this session, **When** suggestions are shown, **Then** songs already sung in this session are not offered again.
5. **Given** suggestions are being fetched, **When** the fetch is slow or fails, **Then** playback is unaffected and the suggestion area degrades without an error interrupting the performance.

---

### User Story 3 - Follow the words (Priority: P2)

The singer needs to see the lyrics with a clear indication of where they are in the song, large enough to read from across a room on an iPad.

**Why this priority**: Equal in practical importance to P2 controls — a singer who does not know the words cannot perform. Separated from P1 because most karaoke sources already carry the words in the video image, so P1 remains viable alone.

**Independent Test**: Play a source whose video carries the words and confirm the image is displayed legibly and stays in step with the audio. Separately, play a source for which a synchronized text track is available and confirm the text advances in step with the audio, including after a seek.

**Acceptance Scenarios**:

1. **Given** a source whose visual carries the words, **When** it plays, **Then** the visual is displayed and remains in step with the audio for the full duration.
2. **Given** a synchronized text track is available for the song, **When** it plays, **Then** the current line is visually distinguished from surrounding lines and advances in step with the audio.
3. **Given** a synchronized text track is displayed, **When** the singer seeks to a different position, **Then** the displayed position corrects itself to match the new audio position.
4. **Given** the app is running on an iPad, **When** words are displayed, **Then** they are legible at a normal room viewing distance.

---

### User Story 4 - Build and run a session (Priority: P3)

A group queues several songs in advance so the party keeps moving without someone searching between every number. Favourites are saved for next time.

**Why this priority**: A quality-of-life layer. Valuable for the real social use case, but every prior story must already work for a queue to be worth anything.

**Independent Test**: Add several songs to a queue, confirm the displayed order, confirm playback advances automatically from one to the next, reorder and remove entries, and confirm saved favourites survive an app restart.

**Acceptance Scenarios**:

1. **Given** search results are displayed, **When** the singer adds items to the queue, **Then** they appear in the queue in the order added.
2. **Given** a queue with remaining items, **When** the current song finishes, **Then** the next item begins without manual intervention.
3. **Given** a queue, **When** the singer reorders or removes an entry, **Then** the change is reflected immediately and the currently playing song is unaffected.
4. **Given** songs were marked as favourites, **When** the app is closed and reopened, **Then** the favourites are still present.

---

### User Story 5 - Sing without the network (Priority: P3)

The singer saves songs ahead of time so a party at a venue with poor connectivity still works.

**Why this priority**: Removes the single largest reliability risk (network) but only matters once the app is already worth using offline.

**Independent Test**: Save several songs while connected, disable all network access on the device, and confirm the saved songs still search (locally), load, and play, while unsaved songs fail with a clear message rather than a hang.

**Acceptance Scenarios**:

1. **Given** network access is available, **When** the singer saves a song for offline use, **Then** progress is shown and completion is indicated.
2. **Given** a song was saved and the device has no network access, **When** the singer plays it, **Then** it plays with the same audio quality as when online.
3. **Given** the device has no network access, **When** the singer attempts to play an unsaved song, **Then** a clear message explains the song is unavailable offline.
4. **Given** stored songs occupy device space, **When** the singer reviews storage, **Then** the space used is shown and individual songs can be removed.

---

### Edge Cases

- **Source is withdrawn or restricted**: the chosen song is deleted, made private, age-restricted, or region-blocked between search and playback. The singer must get a clear explanation and the queue must continue rather than stall.
- **Resolution fails**: the mechanism that turns a search result into a playable audio stream stops working (a common, expected failure — see *Legal & Operational Risk*). The app must fail loudly with a diagnosable message, not silently return no results.
- **Playback address expires**: a resolved stream address becomes invalid mid-song or while queued. Playback must re-resolve and resume rather than drop the performance.
- **Bluetooth delays the audio behind the screen**: the speaker adds output delay, so the words run ahead of the sound the room hears. The app must compensate so the display matches what is audible, not what has merely been transmitted. This is the normal case, not an exception — it applies to every song on the only supported route.
- **Bluetooth link degrades mid-song**: interference or distance causes stutter or a codec downgrade. The app must not mistake a link problem for a playback problem, and must not re-resolve the stream in response to it.
- **Speaker drops mid-song**: the Bluetooth connection is lost and audio would fall back to the device's own tiny speaker at party volume. The app must pause rather than blast the room.
- **Speaker reconnects**: the link returns. The app must offer to resume at the position where it paused rather than restarting the song.
- **Reported Bluetooth delay is wrong**: the speaker misreports its latency, so automatic compensation leaves a visible gap. The singer must be able to trim it by hand.
- **Suggestions are empty or irrelevant**: the upstream offers no relation data for an obscure karaoke upload. The app must fall back to the singer's own history rather than showing nothing.
- **Suggestions repeat what was just sung**: the obvious failure of a naive implementation. Songs performed this session must be excluded.
- **Interruption**: a phone call, alarm, or voice assistant interrupts. Playback must pause and offer to resume rather than silently die.
- **App backgrounded or screen locked**: audio must continue, and standard system playback controls must work.
- **Storage exhausted**: saving a song fails for lack of space. The failure must be explicit and must not corrupt existing saved songs.
- **Unavailable audio format**: the highest-quality rendition is in a form the device cannot play. The system must fall back to the best playable rendition rather than fail.
- **Search returns nothing useful**: the term matches no karaoke version. The singer must be able to refine or supply a direct source reference.
- **Signing expires**: the sideloaded app's signature lapses and it refuses to launch. The singer must know in advance that this will happen and how to recover.
- **Very long source**: a multi-hour compilation is selected. Resolution, seeking, and memory use must stay bounded.

## Requirements *(mandatory)*

### Functional Requirements

**Source and search**

- **FR-001**: System MUST let the singer find karaoke sources on YouTube by text search from inside the app, returning at minimum title, channel, and duration per result.
- **FR-002**: System MUST let the singer supply a direct YouTube reference (link or identifier) as an alternative to search.
- **FR-003**: System MUST resolve a chosen source to a playable audio rendition without launching, embedding, or depending on the installed YouTube application.
- **FR-004**: System MUST select the highest-quality audio rendition that the device can play, and MUST fall back to the next-best playable rendition when the best is undecodable.
- **FR-005**: System MUST surface the selected rendition's quality (format and bitrate) to the singer on request, so the "highest quality" claim is verifiable rather than assumed.
- **FR-006**: System MUST NOT present advertising of any kind — pre-roll, mid-roll, banner, or interstitial — at any point in the singer's journey.
- **FR-007**: System MUST re-resolve and resume playback when a previously resolved stream address has expired, without ending the performance.
- **FR-008**: System MUST report resolution failures with a message that distinguishes "this song is unavailable" from "the resolution mechanism is broken".

**Audio playback**

- **FR-009**: System MUST play the backing track through the device's selected output route, applying no processing to the decoded audio beyond level control.
- **FR-010**: System MUST NOT capture microphone input, request microphone permission, or apply vocal processing of any kind. Vocals are entirely the PA speaker's responsibility.
- **FR-011**: System MUST NOT alter the pitch or tempo of the backing track. Songs play as published.
- **FR-012**: System MUST select and play the best rendition available rather than attempting to improve a lesser one by processing.
- **FR-013**: System MUST let the singer control output volume, with changes taking effect without audible artefacts.
- **FR-014**: System MUST report the active output route to the singer, and MUST indicate when the route is one that degrades audio quality.
- **FR-015**: System MUST continue audio playback when the app is backgrounded or the screen is locked, and MUST respond to the system's standard playback controls and show current track information there.
- **FR-016**: System MUST pause on audio interruption and offer resumption when the interruption ends.
- **FR-017**: System MUST handle output route changes without crashing or losing playback position.
- **FR-018**: System MUST pause rather than continue when the active output route is lost and playback would fall back to the device's built-in speaker.
- **FR-019**: System MUST compensate on-screen word timing for the active output route's delay, so the display matches the sound the room hears rather than the sound the device has dispatched.
- **FR-020**: System MUST let the singer manually adjust the display-versus-audio offset, for routes whose delay the system reports inaccurately.

**Words on screen**

- **FR-021**: System MUST display the source's visual content when that visual carries the words, keeping it in step with the audio.
- **FR-022**: System SHOULD display a synchronized text track, with the current position visually distinguished, when such a track is available for the song.
- **FR-023**: System MUST correct the displayed word position after a seek, so that text and audio agree.
- **FR-024**: System MUST render words legibly at a room viewing distance on iPad, and MUST let the singer change the text size.

**Suggestions**

- **FR-025a**: System MUST offer a list of suggested next songs for the song currently playing or just finished, showing title, channel, and duration for each.
- **FR-025b**: System MUST produce suggestions even when the upstream offers no relation data for the current song, falling back to candidates derived from the singer's own history, favourites, and the current song's channel.
- **FR-025c**: System MUST exclude songs already performed in the current session from the suggestion list.
- **FR-025d**: System MUST NOT let suggestion fetching delay, interrupt, or fail playback. A suggestion failure degrades the suggestion area only.
- **FR-025e**: Users MUST be able to add a suggestion to the queue, or play it immediately, with the same interaction a search result offers.
- **FR-025f**: System MUST indicate where each suggestion came from, so the singer can tell an upstream relation from a local-history guess.

**Session management**

- **FR-025**: Users MUST be able to queue multiple songs, view the queue order, reorder it, and remove entries.
- **FR-026**: System MUST advance to the next queued song automatically when the current song ends.
- **FR-027**: Users MUST be able to mark songs as favourites, and favourites MUST survive app restart.
- **FR-028**: System MUST retain the singer's audio control settings (key, tempo, balance, effects) across songs and across app restarts.

**Offline**

- **FR-029**: Users MUST be able to save a song for offline playback, with visible progress and a clear completion state.
- **FR-030**: System MUST play saved songs with no network access, at the same audio quality as the online playback of the same song.
- **FR-031**: System MUST show how much device storage saved songs occupy and MUST let the singer remove individual saved songs.
- **FR-032**: System MUST fail clearly, not hang, when an unsaved song is requested with no network access.
- **FR-033**: System MUST NOT corrupt existing saved songs when a save fails for lack of space.

**Operation and privacy**

- **FR-034**: System MUST operate without requiring the singer to create an account or sign in to a service operated by this app.
- **FR-035**: System MUST keep all personal data — search history, favourites, queue, saved audio, recordings if any — on the device, and MUST NOT transmit it to any service operated by this app.
- **FR-036**: System MUST make the signing-expiry constraint visible to the singer, including how much validity remains and how to restore it.

### Key Entities *(include if feature involves data)*

- **Song**: a karaoke source the singer can perform. Identified by its upstream reference. Carries title, channel/uploader, duration, and a thumbnail. Is the thing that appears in search results, queues, and favourites.
- **Audio Rendition**: one of several available audio-only forms of a Song, differing in format, bitrate, and channel count. Exactly one is selected for a given playback, by the quality rule in FR-004.
- **Stream Address**: a time-limited, resolved address through which an Audio Rendition can be fetched. Has an expiry. Expiry is the trigger for FR-007.
- **Saved Song**: a Song whose chosen Audio Rendition has been written to device storage, with the bytes, the format metadata, the time saved, and the space occupied. Satisfies FR-029 through FR-033.
- **Performance Settings**: the singer's controls — output volume, the display-versus-audio offset, and text size. Persist across songs and restarts per FR-028.
- **Suggestion**: a candidate next Song, carrying which strategy produced it and how strongly it is recommended. Transient — regenerated per song, never persisted.
- **Queue**: an ordered list of Songs awaiting performance, plus which entry is current. Mutable while playing.
- **Favourite**: a Song the singer marked for easy return. Persists across restarts.
- **Lyrics Track**: a time-ordered sequence of text segments for a Song, each with a start time, optionally with finer-grained word timings. Optional — a Song may have none.
- **Playback Session**: the live state of one performance — which Song, which Audio Rendition, current position, playing or paused, and which output route is active with its measured delay.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From launching the app, a singer finds a specific song by name and hears it playing in under 30 seconds, on first attempt, without instruction.
- **SC-002**: Zero advertisements are presented across a continuous 60-minute session covering at least 15 songs.
- **SC-003**: Zero microphone-related permission prompts appear across the entire app, and a device privacy inspection confirms the app never accesses the microphone.
- **SC-004**: The selected audio rendition is, in at least 95% of attempted songs, the highest-quality rendition the source offers that the device can decode — verified by comparing the app's reported selection against the renditions actually available.
- **SC-005**: Resolution succeeds for at least 95% of a fixed 50-song reference list on any given day, and every failure produces a message that correctly distinguishes an unavailable song from a broken mechanism.
- **SC-006**: Playback begins within 5 seconds of selection on a typical home connection, and within 1 second for a saved song.
- **SC-007**: Volume changes take audible effect within 200 ms and introduce no audible click, gap, or dropout. Audio output is bit-identical to the decoded source apart from level, verified by capture.
- **SC-008**: Displayed words stay within 150 ms of the audio **as heard from the Bluetooth PA speaker** over a full song, including after three seeks.
- **SC-014**: Suggestions appear for at least 90% of songs played, within 3 seconds of the song starting, and never block or delay playback. No song already performed in the session appears as a suggestion.
- **SC-009**: A 2-hour continuous session completes with no crash, no audio dropout, and no unbounded growth in memory or storage.
- **SC-010**: Audio continues uninterrupted when the app is backgrounded and when the screen locks, and standard system playback controls operate correctly.
- **SC-011**: With all network access disabled, every previously saved song plays successfully, and every unsaved song produces a clear unavailability message within 3 seconds rather than a hang.
- **SC-012**: Zero bytes of singer data leave the device to any service operated by this app, verified by network capture over a full session.
- **SC-013**: Queue, favourites, and performance settings survive app restart with no loss, across 10 consecutive restarts.

## Assumptions

- **Distribution is personal sideloading**, confirmed with the user. The app is installed via AltStore or direct Xcode install onto the singer's own devices. App Store submission is explicitly out of scope, because sourcing media outside the official player conflicts with App Store review policy.
- **The singer accepts the signing-expiry burden** inherent to sideloading and will re-sign the app on the required cadence. FR-036 exists to make this visible rather than surprising.
- **One user, personal use.** No multi-user accounts, no server operated by this app, no shared library, no social features. Scale is a single household.
- **Target devices are iPhone and iPad on a recent iOS version.** The exact minimum version is a plan-phase decision driven by the audio APIs selected.
- **A portable PA speaker ("loa kéo") handles all vocal duties**, confirmed with the user. The microphone plugs into that speaker, which supplies its own preamp, echo/reverb, and vocal-versus-music mixing in hardware. The app's only contribution is the backing track it sends to that speaker. This removes microphone capture, live monitoring latency, acoustic feedback, and vocal effects from the problem entirely.
- **The connection to the PA speaker is Bluetooth**, confirmed with the user. This is the single supported route and the app is designed around it. Two consequences are accepted knowingly, and both are documented in *Audio Quality Reality* below: Bluetooth re-encodes the audio, and it delays it by enough to desynchronise the words unless compensated (FR-019).
- **Pitch and tempo are never altered**, confirmed with the user. Songs play as published. The app selects the best rendition rather than trying to improve a lesser one, which also means the audio output is the decoded source with nothing applied but level.
- **Suggestions are a convenience, not a guarantee.** The upstream no longer offers a documented relation endpoint, so suggestion quality will vary and will sometimes fall back to the singer's own history. FR-025b exists so an empty list never happens.

## Audio Quality Reality

The original request asked for the highest possible audio quality. The Bluetooth decision constrains that in a way worth stating plainly rather than discovering later.

Bluetooth audio is **always re-encoded**. The decoded backing track is compressed again by the phone, transmitted, and decompressed by the speaker. Because the source is already a lossy stream, this is a lossy-to-lossy transcode, and it is the narrowest point in the whole chain. The practical consequences:

- The audio quality ceiling is set by the **Bluetooth link**, not by which rendition is chosen upstream. Choosing a nominally better rendition yields a smaller real-world improvement than it would over a cable.
- A cable connection to the same speaker would avoid the re-encode entirely and is the single largest quality improvement available. It is not chosen here, by the user's decision.
- The app must therefore not claim an audio quality it cannot deliver. FR-005 reports the actual rendition, and FR-014 requires the app to indicate that the active route degrades quality.

This does not change what the app should build. It changes which effort is worth spending: chasing the last few percent of upstream rendition quality has a poor return over Bluetooth, while getting the word-timing compensation right has a very good one.
- **Karaoke sources are assumed to already be karaoke versions.** The app does not attempt to remove a lead vocal from an ordinary recording; it plays what the source provides.
- **Most karaoke sources carry the words in the video image.** A separate synchronized text track is treated as an enhancement (FR-022, SHOULD) rather than a requirement, because coverage cannot be guaranteed.
- **The device has a working network connection for search and for first playback of any song.** Offline operation (User Story 5) applies only to songs previously saved.
- **Resolution of a source to a playable stream is expected to break periodically** when the upstream service changes. This is an accepted, ongoing maintenance cost, not a defect to be designed away. FR-008 and SC-005 exist to make breakage diagnosable.

## Legal & Operational Risk

Recorded here because it shaped the distribution decision and constrains everything downstream.

- Retrieving media from YouTube outside its official player, and bypassing advertising, is contrary to YouTube's Terms of Service. This specification does not assert otherwise.
- An app built to this specification would be rejected under App Store review policy governing third-party content. Personal sideloading was chosen by the user with this understood.
- Karaoke recordings on the source platform are themselves third-party content with their own rights. Use is personal and non-commercial.
- The resolution mechanism depends on undocumented upstream behaviour and will break without notice. Ongoing maintenance is a condition of the app continuing to work.
