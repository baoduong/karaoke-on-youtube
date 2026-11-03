# Karaoke-on-YouTube Constitution

A single-developer, personally-sideloaded iOS/iPadOS karaoke application. These principles exist to keep a hobby-scale project honest about where its real risk lives: an unstable upstream dependency and a real-time audio path that cannot be debugged after the fact.

## Core Principles

### I. The Audio Path Is Sacred

The real-time audio render thread is the one place in this codebase where ordinary engineering habits are wrong. No allocation, no locking, no Swift runtime dynamism, no logging, no Objective-C message sends inside a render callback. Every parameter the UI can change reaches the audio thread through a lock-free mechanism. Any pull request that touches a render callback states explicitly which operations it performs and why each is real-time safe. A glitch, click, or dropout is a defect of the same severity as a crash — the singer experiences them identically.

### II. The Upstream Will Break — Design For That

Resolving a source to a playable stream depends on undocumented third-party behaviour that changes without notice. This is a certainty, not a risk. Therefore: every upstream interaction sits behind a protocol with at least one alternative implementation; every failure distinguishes "this item is unavailable" from "our mechanism no longer works"; and the breakage surface is one named module, never scattered through the app. When it breaks, the fix must be confined to that module and must be deployable the same day.

### III. Verify the Claim, Not the Code Path

Each requirement in the specification carries a measurable success criterion. "Highest audio quality" means the app can report which rendition it chose and that choice is checkable against what was available. "No advertising" means a session is observable end to end and ads are counted at zero. "Low latency" means a number measured on a device, not an assertion that the right API was called. A feature is done when its criterion is measured on real hardware — simulator results do not count for anything involving audio, microphone, or network timing.

### IV. Test What Can Silently Rot

Automated tests are mandatory for pure logic that fails quietly: rendition selection and ranking, lyric timing and seek correction, queue state transitions, cache accounting and eviction, settings persistence, and every parser handling upstream data. Automated tests are not required for SwiftUI view layout or for audio graph wiring, which are verified by ear and by instrument on a device. Tests that pin prose, assert a mock was called, or restate the implementation are rejected; a test that cannot fail is worse than no test because it buys false confidence.

### V. Nothing Leaves the Device

This app operates no server and holds no account. Search history, favourites, queue, saved audio, performance settings, and any recording stay on the device. There is no analytics, no crash reporting to a third party, no telemetry. The only outbound traffic is to the upstream media source and, optionally, a lyrics service the user explicitly enables. This is verifiable by network capture and will be verified that way.

### VI. Honest Failure Over Silent Degradation

When something cannot work, the singer is told, in terms describing their situation rather than ours: the song is unavailable, the connection is gone, the microphone is muted, the signature expires in three days. Empty states, infinite spinners, and swallowed errors are defects. An error the user cannot act on must at minimum be distinguishable in a log the maintainer can read.

### VII. One Developer's Scale

This project is maintained by one person in spare time. Every abstraction must pay for itself within the current feature set. No dependency injection framework, no architecture pattern applied for its own sake, no module boundary without a second implementation behind it or a real-time-safety reason for it. The protocol boundaries this constitution mandates (Principle II) exist because the upstream genuinely breaks — that is the bar every other abstraction must also clear.

## Legal and Distribution Constraints

Distribution is personal sideloading only. App Store submission is out of scope and no work is spent on App Store compliance.

Sourcing media outside the official player and bypassing advertising is contrary to the upstream service's terms. This is acknowledged, not litigated. Use is personal, non-commercial, single-household. The project does not redistribute media, does not operate a shared service, and does not publish binaries.

Code signing expires. The app surfaces its own remaining validity so expiry is a scheduled chore rather than a mystery failure.

## Quality Gates

A change is complete when all of the following hold:

1. It builds for a physical device with no new warnings.
2. Any claim it makes about audio, latency, network, or microphone behaviour has been measured on a physical device.
3. Logic that can rot silently (Principle IV) is covered by a test that was observed to fail before the fix.
4. Render-callback changes carry an explicit real-time-safety note.
5. New upstream interaction is behind the Principle II boundary.
6. No new outbound destination was introduced without a corresponding note in this constitution's privacy principle.

A release — meaning a build installed on a device for actual singing — additionally requires a continuous session of at least thirty minutes with no crash, no dropout, and no advertisement.

## Governance

This constitution governs the project. Where it conflicts with a convenient implementation, the constitution wins or the constitution is amended first, in a separate change, with the reasoning recorded.

Amendments are made by editing this file, bumping the version, and stating what changed and why. Version numbering is MAJOR.MINOR.PATCH: MAJOR for removing or reversing a principle, MINOR for adding a principle or materially expanding one, PATCH for clarification that changes no behaviour.

Principle VII cuts both ways: these rules are themselves subject to paying for themselves. A gate that produces no defect findings over a sustained period is a candidate for removal, by amendment.

**Version**: 1.0.0 | **Ratified**: 2026-11-03 | **Last Amended**: 2026-11-03
