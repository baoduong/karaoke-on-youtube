# Contract: Tone control

**Feature**: 002-equalizer | **Date**: 2026-11-03

Extends `contracts/audio-pipeline.md`. Where the two disagree, the audio
pipeline contract wins — this one only adds.

---

## Pipeline surface

```swift
/// Apply the singer's tone control. Safe to call during playback.
func setEqualizer(_ settings: EqualizerSettings)

/// False when the platform could not splice the control into what is loaded.
var isEqualizerAvailable: Bool { get }
```

`setEqualizer` is idempotent, takes effect within 200 ms, and never
interrupts playback. Calling it before anything is loaded is valid: the value
is held and applied to the next item.

`isEqualizerAvailable` is false until a source has loaded, then reflects
whether a tap actually attached. It is not a capability flag for the device —
it is a fact about the item currently playing.

---

## Behavioural requirements

1. **Bypassed means untouched.** With `isEnabled` false, or every band at
   zero, samples reach the output exactly as decoded apart from level. This
   is what keeps SC-007 verifiable by capture. The pass-through is not a
   filter set to 0 dB — the callback returns the source audio without running
   the engine at all.

2. **Attachment is attempted per item, not once.** Each load decides again,
   because the answer depends on the source kind:

   | Source | Mechanism | iOS 26.2 | iOS 27.2 |
   |---|---|---|---|
   | `.local` / `.remote` | `trackID` of the asset's audio track | attaches | attaches |
   | `.hls` | `AVAudioMixInputParametersTrackMixID` (iOS 27+) | refuses | attaches |

   Measured, not inferred — see `research.md` R1 and the attachment suite.

3. **Refusal is reported, never silent.** When no tap could attach, the
   control says so. This exists because the platform's own behaviour is the
   opposite: `AVPlayerItem.audioMix` on HLS before iOS 27 accepts the
   assignment and does nothing. Principle VI makes that unacceptable to copy.

4. **A boost costs level, not headroom.** Output is attenuated by the largest
   positive band gain. No limiter, no normalisation — nothing that changes
   dynamics.

5. **Pitch and tempo are untouched.** This contract adds frequency shaping
   only. FR-011 stands unchanged, and the SwiftLint rule forbidding
   `AVAudioUnitTimePitch` and `AVAudioUnitVarispeed` stays in force.

6. **The tap owns its processor.** `clientInfo` holds a retained reference,
   released in the `finalize` callback. The tap outlives the player item that
   carries it; an unretained pointer there is a use-after-free during
   teardown, which was observed crashing the suite on iOS 26.2 while passing
   on 27.2.

---

## Real-time safety note (Quality Gate 4)

The process callback performs exactly four things:

| Operation | Why it is real-time safe |
|---|---|
| `MTAudioProcessingTapGetSourceAudio` | The API provided for this purpose |
| `engine.manualRenderingBlock` | Apple's render entry point, in `.realtime` mode |
| `memcpy` between buffer lists | No allocation, no locking |
| Property reads on a `final class` via `takeUnretainedValue()` | Direct call, no dynamic dispatch, no retain |

It does not allocate, lock, log, touch Swift collections, or send
Objective-C messages. Every buffer is allocated in `prepare`.

Band gains never cross this callback. They are AudioUnit parameters set from
the main thread and ramped by the unit itself.

**Known imprecision, stated rather than hidden**: in a Debug build, ARC may
emit retain/release traffic around the Swift call from the C callback. It is
not provably allocation-free there. Release builds optimise it out, and the
device verification that SC-015 requires is performed on a Release-signed
build.

---

## Test contract

Automated (Principle IV — logic that rots silently):

- Gain clamping, including non-finite input.
- Headroom arithmetic across boost-only, cut-only, mixed, and bypassed.
- Transparency in all four combinations of enabled and flat.
- Settings round trip through SwiftData, and defaults on a fresh record.
- Attachment to a file-based source, using a generated tone so it needs no
  fixture and no network.

Not automated, by Principle IV and Principle III:

- That the filter sounds correct. Verified by ear on the device.
- Attachment to HLS. Needs a live companion service; recorded as a measured
  result in the attachment suite's documentation instead.
- SC-015's 200 ms and no-click claims. Measured on the device through the
  Bluetooth PA, because simulator audio timing proves nothing.
