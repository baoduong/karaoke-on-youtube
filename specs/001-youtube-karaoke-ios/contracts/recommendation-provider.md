# Contract: RecommendationProvider

**Feature**: `001-youtube-karaoke-ios` | **Phase**: 1 (Design)

Produces a list of suggested next songs for whatever is currently playing, so a party keeps moving without someone searching between every number.

**Satisfies**: FR-025a … FR-025f

## Why this is a blended, multi-strategy contract

The obvious implementation — ask the upstream for related videos — is not available. The platform's public data API no longer exposes a related-videos parameter; it was removed and the current parameter list for the search endpoint does not contain it ([research.md](../research.md) R8, verified against the official reference).

That leaves three realities this contract is shaped around:

1. **No documented relation endpoint exists.** Anything resembling the platform's own "what's next" must be scraped from a player response, which puts it behind the same breakage risk as stream resolution and makes it the least reliable strategy, not the most.
2. **Search quota is scarce.** The search endpoint is capped at roughly a hundred calls per day. Spending search calls to generate suggestions for every song would exhaust the allowance in a single evening, during which the singer also needs search to work.
3. **Local data is free, private, and always available.** History, favourites, and channel affinity cost nothing, never break, and never leave the device.

So the design inverts the naive approach: local strategies are the dependable backbone, and the upstream strategy is an optional enhancement layered on top when it happens to work. That is also what makes FR-025b — never show an empty list — achievable rather than aspirational.

## Protocol

```swift
protocol RecommendationProvider: Sendable {
    var identifier: StrategyID { get }
    var isAvailable: Bool { get }

    /// Candidates for the given song. Returns [] freely — an empty result from
    /// one strategy is normal and is covered by the others.
    func candidates(for songID: SongID,
                    limit: Int) async throws(RecommendationError) -> [Suggestion]
}

protocol RecommendationEngine: Sendable {
    /// Blends every available strategy, applies exclusions, ranks, truncates.
    /// Never throws: a total failure yields an empty list, which the UI shows
    /// as "no suggestions", never as an error (FR-025d).
    func suggestions(for songID: SongID,
                     excluding: Set<SongID>,
                     limit: Int) async -> [Suggestion]
}
```

The engine never throws. A suggestion failure must not surface as an error during a performance — FR-025d makes that a requirement, not a nicety.

## Strategies, in priority order

| Priority | Strategy | Source | Breaks? | Cost |
|---|---|---|---|---|
| 1 | `upstreamRelated` | Platform's own "what's next", via the source provider | **Yes, frequently** | Network |
| 2 | `sameChannel` | More from the same karaoke channel | Rarely | Cheap upstream call |
| 3 | `coOccurrence` | Sung in the same past session as this song | Never | Local |
| 4 | `history` | Previously sung, by play count and recency | Never | Local |
| 5 | `favourite` | A favourite not yet sung this session | Never | Local |

Strategies 3 through 5 are computable entirely from the local store. That is the guarantee behind FR-025b: for any singer who has used the app for more than a few songs, the list is never empty even with no network at all.

**On `upstreamRelated`.** It sits at priority 1 because when it works it is the best signal — it is the thing the user asked for. It is also the only strategy that can break, and it breaks for the same reasons stream resolution breaks. It therefore lives behind `SourceProvider`, inherits that boundary's error taxonomy, and its absence must be completely unremarkable. If it never works, the feature still works.

**On `sameChannel`.** Karaoke channels are unusually strong signal — a singer who liked one upload from a channel will usually accept another, because the channel determines the arrangement style, the key conventions, and the on-screen presentation. This is a better suggestion heuristic for karaoke than it would be for general video, and it is cheap. Per the platform's own guidance, enumerating a channel's uploads is better done through its uploads playlist than through search, which also avoids spending the scarce search quota.

**On `coOccurrence`.** Songs sung in the same past session are related by something no content-based signal captures: this group's actual taste. It costs one local query and tends to produce the suggestions that feel uncanny in a good way.

## Blending

1. Gather candidates from each available strategy concurrently, with a short overall deadline. A strategy that misses the deadline contributes nothing and is not awaited.
2. Deduplicate by `songID`, keeping the highest-priority strategy's attribution.
3. Apply the exclusion rules (below).
4. Rank by strategy priority, then by `score` within a strategy.
5. Truncate to the requested limit.

The deadline is what keeps FR-025d true: the whole operation is bounded, so a slow upstream cannot leave the suggestion area spinning while a song finishes.

## Exclusion rules

1. The currently playing song.
2. Every song in the session's performed set (FR-025c). **This is the rule whose absence makes a suggestion list visibly stupid** — offering the song that just finished is the failure everyone notices immediately.
3. Songs already queued as `waiting`. Suggesting what is already coming wastes a slot.
4. Songs whose last resolution failed with a content-side error this session. Suggesting a song known to be unavailable is worse than suggesting nothing.

## Errors

```swift
enum RecommendationError: Error {
    case strategyUnavailable
    case upstreamFailed(detail: String)
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
}
```

Individual strategies may throw; the engine absorbs every one. No `RecommendationError` reaches the singer. Upstream failures are recorded locally so a maintainer can see that `upstreamRelated` has stopped working — which, per Principle VI, must be visible to the maintainer even when it is invisible to the singer.

## Behavioural requirements

1. **Never blocks playback** (FR-025d). Suggestions are fetched concurrently with everything else, under a deadline. The time-to-first-audio budget in SC-006 is unaffected.
2. **Never empty for an established singer** (FR-025b). Local strategies guarantee it. The sole exception is cold start with no history and no upstream data, which must say so plainly rather than render an empty list as a loading state.
3. **Attribution is shown** (FR-025f). Each suggestion carries a short, singer-facing reason. The difference between "more from this channel" and "you sang this last month" changes how much the singer trusts it.
4. **Refreshes with the current song.** Suggestions are regenerated when the current song changes and are never cached across songs — the exclusion set changes every few minutes, so a cached list is a stale list.
5. **Spends no search quota.** No strategy calls the search endpoint. Channel enumeration uses the cheaper playlist path. This is what keeps search working for the singer all evening.
6. **Stays on the device.** Local strategies read only the local store. Nothing about the singer's taste is transmitted anywhere (Principle V).

## Test contract

Automated (Principle IV — this is exactly the kind of logic that rots silently and fails invisibly):

- **Exclusion correctness**: given a performed set, a queue, and a known-unavailable set, no excluded song appears in the output. The already-sung case is tested explicitly because it is the visible failure.
- **Deduplication and attribution**: a song produced by three strategies appears once, attributed to the highest-priority one.
- **Ranking**: ordering follows strategy priority first, then score, deterministically for a fixed input.
- **Engine never throws**: with every strategy failing, the engine returns an empty list rather than propagating an error.
- **Deadline**: a strategy that exceeds the deadline is excluded and does not extend total time.
- **Local-only guarantee**: with the upstream strategies disabled and a populated store, the result is still non-empty.
- **Cold start**: empty store and no upstream yields an empty list and the explicit "no suggestions" state, distinguishable from a loading state.

Not tested automatically: whether the suggestions are *good*. That is judged by using the app at a real party, which is Scenario 12 in [quickstart.md](../quickstart.md). A unit test cannot tell a sensible suggestion from a silly one, and pretending otherwise would be the kind of test the constitution rejects.
