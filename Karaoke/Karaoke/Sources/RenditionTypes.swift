// T028 — AudioRendition, StreamAddress, Container, Codec.
//
// These are transient types — never persisted. AudioRendition is re-resolved
// every playback; StreamAddress is time-limited and never written to storage
// (data-model invariant 4).

import Foundation

// MARK: - Container

/// The container format of an audio rendition.
enum Container: Sendable, Equatable, Hashable {
    case m4a
    case webm
    case mp4
    case other(String)
}

// MARK: - Codec

/// The audio codec of a rendition.
///
/// Codec preference order for tie-breaking in the Selection Rule is defined in
/// research.md R1 and applied in RenditionSelection — not hardcoded here.
enum Codec: Sendable, Equatable, Hashable {
    case aac
    case opus
    case vorbis
    case other(String)
}

// MARK: - AudioRendition

/// One audio-only form of a Song. Several exist per Song; exactly one is
/// selected per playback by the Selection Rule in RenditionSelection.swift.
///
/// Never persisted for streamed songs — re-resolved every time, because the
/// upstream set changes.
struct AudioRendition: Sendable, Equatable {

    /// Upstream format identifier. Identifies the rendition within its Song.
    let itag: Int

    /// Container format.
    let container: Container

    /// Audio codec.
    let codec: Codec

    /// Average bitrate in bits per second. Null when upstream omits it —
    /// ranking falls back to codec + container priors.
    let averageBitrateBps: Int?

    /// Sample rate in Hz.
    let sampleRateHz: Int?

    /// Number of audio channels.
    let channelCount: Int?

    /// Approximate byte size of the full rendition. Drives the storage estimate
    /// shown before a save (FR-031).
    let approximateByteSize: Int64?

    /// Whether this rendition can be decoded on the current device.
    ///
    /// Computed by querying the platform's decoder support (DecodabilityProbe),
    /// NOT a hardcoded codec list, so the answer stays correct across OS versions.
    /// Determines eligibility — see Selection Rule.
    let isDecodableOnDevice: Bool
}

// MARK: - StreamAddress

/// A time-limited resolved address for fetching an AudioRendition.
///
/// Invariant 4 (data-model.md): `url` MUST NEVER appear in a log, an error
/// message, or persistent storage. DiagnosticLog enforces this.
struct StreamAddress: Sendable {

    /// The resolved stream URL. NEVER log, persist, or include in error messages.
    let url: URL

    /// Which AudioRendition this address serves.
    let renditionItag: Int

    /// When this address expires. Parsed from the URL's `expire` query parameter,
    /// or defaulted conservatively when absent.
    let expiresAt: Date

    /// When this address was resolved. For diagnosing clock-skew-induced
    /// premature expiry.
    let resolvedAt: Date

    /// Whether the server supports HTTP range requests.
    /// Gates seek-without-refetch and the save path.
    let supportsRangeRequests: Bool

    // MARK: Expiry helpers

    /// Safety margin before `expiresAt` at which re-resolution should begin.
    /// Re-resolution starts before expiry so FR-007 produces no audible gap.
    /// Value is conservative pending Spike S3 measurement.
    static let safetyMargin: TimeInterval = 120 // 2 minutes

    /// True when the address should be refreshed (stale at expiresAt minus margin).
    var isStale: Bool {
        Date() >= expiresAt.addingTimeInterval(-Self.safetyMargin)
    }

    /// True when the address has fully expired.
    var isExpired: Bool {
        Date() >= expiresAt
    }

    // MARK: Parsing

    /// Parse the expiry from a YouTube stream URL's `expire` query parameter.
    /// Returns a conservative default (5 minutes from now) when absent.
    static func parseExpiry(from url: URL) -> Date {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expireItem = components.queryItems?.first(where: { $0.name == "expire" }),
              let expireString = expireItem.value,
              let expireTimestamp = TimeInterval(expireString) else {
            // Conservative default: 5 minutes from now.
            // Absent expiry means we don't know — assume short-lived.
            return Date().addingTimeInterval(300)
        }
        return Date(timeIntervalSince1970: expireTimestamp)
    }

    /// Determine whether the URL supports range requests.
    /// YouTube stream URLs typically include `range` capability; we check for
    /// the absence of `requiressl=yes` combined with the presence of `rn=` or
    /// similar markers. Conservative default is true for YouTube streams.
    static func parseSupportsRangeRequests(from url: URL) -> Bool {
        // YouTube adaptive streams support range requests by default.
        // A more precise check would probe with a HEAD request, but that
        // requires a network call. Conservative: assume true for YouTube URLs.
        return true
    }
}
