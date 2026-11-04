# Specification Quality Checklist: Professional iPhone and iPad Interface

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-11-04
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

All items pass. The specification is ready for `/speckit.plan`.

### The clarification that reshaped this specification

One question was raised during drafting: whether the iPad is a control surface used beside a
television, or is itself the screen people sing from. The owner's answer went further than the
question — **no television is used, on any device.**

That answer invalidated the framing of the first draft, which opened with a song playing on a
television, and it was rewritten rather than patched. What changed:

- The device is now understood as the lyrics display. The karaoke video carries its words in
  the picture, which the source code already states in four places.
- A new Story 1 was added at P1 — keeping the words readable — and the former P1, one-handed
  reachability, moved to P2. Legibility outranks reach: a singer who cannot reach a control
  still finishes the song.
- The design consultation's recommended iPad layout, a two-column "party station" giving about
  40% of the display to search, was rejected. With no television, that would take space from
  the only thing being read.
- A defect was identified that the first draft had missed: the tone panel slides up over the
  video, so adjusting tone mid-song hides the lyrics. That is now FR-002 and SC-002.
- Landscape was found to be permitted on both device classes with no layout written for it.
  With a television ruled out, turning the device sideways is the only way to enlarge the
  words on a phone, so it became FR-004 and SC-003.

### Validation evidence

Checks performed mechanically against `spec.md` rather than by reading:

- 29 functional requirements, FR-001 to FR-029, no gaps and no duplicates.
- 14 success criteria, SC-001 to SC-014, no gaps and no duplicates.
- 5 user stories at distinct priorities P1 to P5, each with a "Why this priority", an
  "Independent Test", and at least two acceptance scenarios.
- No framework, language, or API name appears anywhere. Platform terms were deliberately
  translated: layout decisions read as "available width" rather than naming a size-class API,
  and the iPad Library behaviour reads as "collections stay visible" rather than naming a
  split-view container.
- Every success criterion names how it is measured. Nine require a physical device, which
  matches the constitution's Principle III.

### Rejected during drafting

- A key / pitch transposition control was proposed during design consultation and rejected.
  The audio pipeline states in four places that pitch and tempo processing are deliberately
  excluded (FR-011 of feature 001), and adding it would require a real-time render thread the
  app does not have. It appears nowhere in this specification.
- A requirement to add a cancel action to the "Starting song…" overlay was dropped after
  checking: that control already exists.
- The concept mockups under `specs/karaoke_ui_concept_screens/` were read and then set aside.
  They are excluded from the repository by `.gitignore` as "low-resolution reference", they
  predate the design system, they show a lyrics layer that commit `a62185c` removed, and they
  omit the tone control that commit `3b57737` added. No requirement here derives from them.
