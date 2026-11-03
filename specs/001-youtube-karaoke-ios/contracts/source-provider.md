# Contract: SourceProvider

**Feature**: `001-youtube-karaoke-ios` | **Phase**: 1 (Design)

The boundary mandated by Constitution Principle II — *The Upstream Will Break*. Every interaction with YouTube passes through this protocol. Nothing outside the module implementing it may know that YouTube exists.

**Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008

## Why this boundary exists

Resolving a video to an audio stream depends on undocumented upstream behaviour that changes without notice. When it breaks, the fix must be confined to one module and deployable the same day. This contract is the seam that makes that possible — and the reason at least two implementations must exist from day one, so the fallback path is exercised rather than theoretical.

## Protocol

```swift
protocol SourceProvider: Sendable {
    /// Stable identifier for diagnostics and for reporting which implementation served a request.
    var identifier: SourceProviderID { get }

    /// Whether this provider is currently usable. Checked before routing; a provider that
    /// knows it is broken reports false rather than failing every call.
    func healthCheck() async -> ProviderHealth

    /// FR-001. Text search returning candidate karaoke sources.
    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata]

    /// FR-002. Resolve a direct reference (URL or bare identifier) to metadata.
    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata

    /// FR-003, FR-004. Enumerate every audio-only rendition the upstream offers.
    /// Selection is NOT performed here — this returns the full set so the pure
    /// selection function in the audio layer can rank it and so SC-004 is verifiable.
    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition]

    /// FR-007. Produce a playable address for one rendition. Called again when the
    /// previous address nears expiry; must be safe to call repeatedly.
    func streamAddress(for songID: SongID,
                       itag: Int) async throws(SourceError) -> StreamAddress
}
```

`SourceReference` accepts a full URL, a shortened URL, or a bare identifier, and normalises to a `SongID`. A reference it cannot parse is `SourceError.malformedReference` — never a network call that fails later.

## Error contract

The single most important part of this document. FR-008 and SC-005 require the app to distinguish *this song is unavailable* from *our mechanism is broken*, because those have different audiences: the first is the singer's problem to route around, the second is the maintainer's to fix.

```swift
enum SourceError: Error {
    // ── Content-side: the song cannot be played. Singer-facing. Queue advances. ──
    case notFound(SongID)
    case private_(SongID)
    case removed(SongID)
    case regionBlocked(SongID, region: String?)
    case ageRestricted(SongID)
    case liveStreamUnsupported(SongID)
    case noAudioRenditions(SongID)

    // ── Mechanism-side: our code no longer works. Maintainer-facing. Loud. ──
    case resolutionFailed(SongID, stage: ResolutionStage, detail: String)
    case upstreamContractChanged(detail: String)
    case cipherFailure(detail: String)

    // ── Environment: neither party is at fault. Retryable. ──
    case offline
    case timeout(stage: ResolutionStage)
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExhausted(resetAt: Date?)

    // ── Caller fault. ──
    case malformedReference(String)
    case unknownItag(SongID, itag: Int)
}

enum ResolutionStage {
    case fetchingPage, parsingPlayerResponse, extractingCipher,
         evaluatingCipher, parsingFormats, buildingAddress
}
```

**Classification rules**

- A content-side error means the upstream explicitly said this item is unavailable. If the upstream said nothing and our parser simply failed, that is `resolutionFailed`, never `notFound`. Misclassifying a mechanism failure as "song unavailable" is the specific failure mode that hides breakage until the whole library appears empty — SC-005 exists to catch it.
- `resolutionFailed` carries the `stage` so a maintainer can tell a markup change from a cipher change without a debugger.
- `upstreamContractChanged` is raised when parsing succeeds structurally but produces impossible values. It is a louder signal than `resolutionFailed`.
- Only environment errors are retried automatically. Content-side and mechanism-side errors are never silently retried — retrying a broken parser just burns the quota.

**Observability** (Constitution Principle VI): every mechanism-side error is recorded locally with stage, timestamp, and a redacted detail string. `StreamAddress.url` never appears in a log, an error message, or persistent storage (data-model invariant 4).

## Implementations

Two, from the start. Principle II requires the alternative to exist, and Principle VII permits this abstraction *only because* the second implementation is real.

| | **OnDeviceSourceProvider** | **CompanionSourceProvider** |
|---|---|---|
| Where resolution happens | In-app | Self-hosted service on the singer's own LAN |
| Breaks when upstream changes | Yes — needs an app rebuild and re-sign | No — update the service, app untouched |
| Works away from home | Yes | Only with remote access to the service |
| Setup cost | None | Requires running a service |
| Role | Default | Fallback, and the escape hatch when on-device breaks |

The rebuild-and-re-sign cost of fixing `OnDeviceSourceProvider` is exactly why the companion exists: re-signing is a chore the singer must perform (FR-036), so a resolution break that requires it is far more disruptive than one fixed server-side.

**Search** uses the official Data API when a key is configured (quota-limited, documented, stable) and falls back to the active provider's own search otherwise. Search and resolution are independently swappable — search breaking and resolution breaking are different events.

### Routing

```swift
actor SourceProviderRouter: SourceProvider {
    init(ordered: [any SourceProvider])
}
```

Tries providers in order, skipping any whose `healthCheck()` reports unhealthy. A content-side error from the first provider is returned immediately — a song that is genuinely private is private for every provider, and trying again only wastes time. A mechanism-side or environment error falls through to the next provider. The identifier of the provider that served the request is recorded on the `PlaybackSession` so FR-005 reporting and SC-005 attribution are possible.

## Behavioural requirements

1. **Pure selection, elsewhere.** `audioRenditions` returns everything; ranking happens in a pure function outside this protocol (see [data-model.md](../data-model.md), Selection Rule). A provider must never pre-filter to "the best one" — that would make SC-004 unverifiable.
2. **Decodability is the device's answer.** `AudioRendition.isDecodableOnDevice` is determined by querying the platform's decoder support, not a hardcoded codec list, so the answer stays correct as the OS changes.
3. **Re-resolution is idempotent.** `streamAddress` may be called repeatedly for the same song and itag. It must not mutate provider state in a way that makes the second call fail.
4. **Cancellation.** Every async method honours task cancellation promptly. A singer who abandons a search must not leave work running.
5. **No UI, no persistence.** This layer performs no user interaction and writes nothing to the store. It returns values.
6. **Bounded work for long sources.** Resolving a multi-hour source must not load the whole thing into memory (spec edge case: *Very long source*).
7. **Timeouts are explicit.** Every network call has a timeout. A hung resolution surfaces as `timeout(stage:)`, which names where it hung.

## Test contract

Per Constitution Principle IV, these are logic that rots silently and therefore must be covered:

- **Reference parsing**: every accepted URL and identifier shape maps to the right `SongID`; malformed input yields `malformedReference` without a network call.
- **Error classification**: a table of recorded upstream responses maps to the correct `SourceError` case. This is the test that catches the misclassification described above, and it is the single highest-value test in the project.
- **Rendition parsing**: recorded format payloads produce the expected `AudioRendition` set, including the cases of absent bitrate and unknown codec.
- **Router behaviour**: content-side error stops the chain; mechanism-side error falls through; unhealthy providers are skipped; the serving provider is attributed correctly.
- **Expiry parsing**: addresses with and without an explicit expiry produce correct `expiresAt`, and the absent case defaults conservatively.

Tests run against recorded fixtures, not the live network — a test suite that depends on YouTube being up is a test suite that fails for the wrong reasons. A separate, manually-run integration check exercises the live path and is the mechanism behind SC-005's daily 50-song reference list.
