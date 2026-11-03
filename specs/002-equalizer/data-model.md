# Phase 1 Data Model: Equalizer

**Feature**: 002-equalizer | **Date**: 2026-11-03

One value type and four persisted fields. There is no new store, no new
entity, and no per-song table — see *Deferred* at the end for why.

---

## EqualizerSettings

A `Sendable`, `Equatable` value type. Crosses actor boundaries, so it holds no
reference and no identity.

| Field | Type | Range | Default |
|---|---|---|---|
| `bassGainDB` | `Double` | −12 … +12 | 0 |
| `midGainDB` | `Double` | −12 … +12 | 0 |
| `trebleGainDB` | `Double` | −12 … +12 | 0 |
| `isEnabled` | `Bool` | — | `false` |

Band centres are fixed and are not stored, because nothing can change them:
`bassFrequency` 100 Hz (low shelf), `midFrequency` 1 kHz (parametric),
`trebleFrequency` 8 kHz (high shelf).

### Validation rules

1. **Every gain is clamped on construction and on every setter.** There is no
   path that puts an out-of-range value into the filter. A hand-edited or
   corrupted store must not push a 40 dB boost into a PA — that is a
   speaker-damage and hearing-safety matter, which is the same reasoning the
   existing `outputVolume` clamping rests on.
2. **A non-finite gain becomes 0.** NaN or infinity reaching an AudioUnit
   parameter is undefined behaviour, not a loud noise.
3. **Default is off and flat.** This is what keeps SC-007's bit-identity claim
   true for anyone who never opens the control.

### Derived values

- **`isTransparent`** — true when the settings cannot change the signal,
  either because `isEnabled` is false or because all three bands sit at zero.
  The player uses it to decide whether the control's icon shows as active.
- **`headroomGainDB`** — the attenuation applied alongside the bands, equal to
  the negative of the largest positive band gain, or 0 when only cutting.
  Boosting material mastered near full scale clips; trading level for
  headroom is the honest fix, and a limiter would be dynamics processing the
  singer did not ask for. Deliberately conservative: it assumes the worst case
  where bands overlap and sum.

### State transitions

None. This is a settings value, not a machine. The only lifecycle is
load → mutate → persist, and the pipeline is told after every mutation.

---

## PerformanceSettings (amended)

The existing SwiftData singleton gains four stored fields:

| Stored | Type | Default |
|---|---|---|
| `_equalizerEnabled` | `Bool` | `false` |
| `_equalizerBassDB` | `Double` | 0 |
| `_equalizerMidDB` | `Double` | 0 |
| `_equalizerTrebleDB` | `Double` | 0 |

They are private, exposed through one computed `equalizer: EqualizerSettings`
accessor that clamps by delegating to the value type. The clamping rule lives
in exactly one place rather than being restated in the model.

Defaults are declared inline on the properties so adding these to a store
that already exists is a lightweight migration rather than a launch failure.

---

## Deferred: per-song gains

The request mentioned specific songs sounding wrong, which argues for
remembering a setting per song. It is not in this model.

Reason: global is the smaller first cut, and it is not yet known whether
re-adjusting per song is actually annoying in use. Adding a per-song table
later requires no redesign — `Song` is already keyed and already carries
play statistics, so a gain triple hangs off it without touching anything
here.

Principle VII: measure the annoyance before building the cure.
