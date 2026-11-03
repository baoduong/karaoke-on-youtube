// T026 — SourceProvider protocol.
//
// The boundary mandated by Constitution Principle II — The Upstream Will Break.
// Every interaction with YouTube passes through this protocol. Nothing outside
// the module implementing it may know that YouTube exists.
//
// Satisfies: FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-008

import Foundation

// MARK: - SourceProvider

/// The seam between the app and any upstream video source.
///
/// Behavioural requirements (contracts/source-provider.md):
/// 1. `audioRenditions` returns the FULL set — selection happens in a pure
///    function (RenditionSelection), never inside a provider.
/// 2. `streamAddress` is idempotent — safe to call repeatedly for the same
///    song and itag without mutating provider state.
/// 3. Every async method honours task cancellation promptly.
/// 4. Every network call has an explicit timeout surfacing as `timeout(stage:)`.
/// 5. No UI, no persistence — this layer returns values only.
protocol SourceProvider: Sendable {

    /// Stable identifier for diagnostics and for reporting which implementation
    /// served a request (FR-005 attribution).
    var identifier: SourceProviderID { get }

    /// Whether this provider is currently usable.
    ///
    /// Checked before routing. A provider that knows it is broken reports
    /// `.unhealthy` rather than failing every call.
    func healthCheck() async -> ProviderHealth

    /// FR-001. Text search returning candidate karaoke sources.
    ///
    /// - Parameters:
    ///   - query: The search string entered by the singer.
    ///   - limit: Maximum number of results to return.
    /// - Returns: Metadata for matching songs, ordered by relevance.
    /// - Throws: `SourceError` — content-side, mechanism-side, or environment.
    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata]

    /// FR-002. Resolve a direct reference (URL or bare identifier) to metadata.
    ///
    /// - Parameter reference: A parsed `SourceReference` normalised to a SongID.
    /// - Returns: Metadata for the referenced song.
    /// - Throws: `SourceError`.
    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata

    /// FR-003, FR-004. Enumerate every audio-only rendition the upstream offers.
    ///
    /// Selection is NOT performed here — this returns the full set so the pure
    /// selection function in RenditionSelection can rank it and so SC-004 is
    /// verifiable offline.
    ///
    /// - Parameter songID: The stable upstream video identifier.
    /// - Returns: All audio-only renditions, unfiltered and unranked.
    /// - Throws: `SourceError`.
    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition]

    /// FR-007. Produce a playable address for one rendition.
    ///
    /// Called again when the previous address nears expiry. Must be safe to
    /// call repeatedly — idempotent with respect to provider state.
    ///
    /// - Parameters:
    ///   - songID: The stable upstream video identifier.
    ///   - itag: The rendition's upstream format identifier.
    /// - Returns: A time-limited stream address.
    /// - Throws: `SourceError`.
    func streamAddress(for songID: SongID, itag: Int) async throws(SourceError) -> StreamAddress
}
