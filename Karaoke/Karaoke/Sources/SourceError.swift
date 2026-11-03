// T027 — SourceError taxonomy and ResolutionStage.
//
// THREE groups, kept separate so the router can classify errors correctly:
//   • Content-side  — the upstream explicitly said this item is unavailable.
//                     Singer-facing. Queue advances. NEVER retry.
//   • Mechanism-side — our code no longer works. Maintainer-facing. Loud.
//                     NEVER silently retry (retrying a broken parser burns quota).
//   • Environment   — neither party is at fault. Retryable.
//
// Classification rule (the most important rule in this file):
//   A content-side error requires the upstream to have EXPLICITLY said the item
//   is unavailable. If the upstream said nothing and our parser simply failed,
//   that is `resolutionFailed`, NEVER `notFound`. Misclassifying a broken
//   parser as "song unavailable" hides breakage until the whole library looks
//   empty — SC-005 exists to catch it.

import Foundation

// MARK: - SongID

/// Stable upstream video identifier. Exactly 11 characters of [A-Za-z0-9_-].
typealias SongID = String

// MARK: - SourceProviderID

/// Stable identifier for a SourceProvider implementation, used in diagnostics
/// and FR-005 attribution.
struct SourceProviderID: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }
}

// MARK: - ProviderHealth

/// Whether a provider is currently usable. Checked before routing.
enum ProviderHealth: Sendable {
    /// The provider is ready to serve requests.
    case healthy
    /// The provider knows it is broken and should be skipped.
    case unhealthy(reason: String)

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
}

// MARK: - SongMetadata

/// Lightweight metadata returned by search and metadata(for:).
/// Not persisted — callers convert to Song for persistence.
struct SongMetadata: Sendable {
    let id: SongID
    let title: String
    let channelName: String
    let durationSeconds: Int
    let thumbnailURL: URL?
}

// MARK: - ResolutionStage

/// Names the stage at which a mechanism-side failure occurred.
/// Carried by `resolutionFailed` and `timeout` so a maintainer can tell a
/// markup change from a cipher change without a debugger.
enum ResolutionStage: Sendable, Equatable {
    case fetchingPage
    case parsingPlayerResponse
    case extractingCipher
    case evaluatingCipher
    case parsingFormats
    case buildingAddress
}

// MARK: - SourceError

/// The complete error taxonomy for the SourceProvider boundary.
///
/// See contracts/source-provider.md for the classification rules.
enum SourceError: Error, Sendable, Equatable {

    // ── Content-side: the song cannot be played. Singer-facing. Queue advances. ──
    // These require the upstream to have EXPLICITLY said the item is unavailable.

    /// The upstream explicitly reported the video does not exist.
    case notFound(SongID)

    /// The upstream explicitly reported the video is private.
    case private_(SongID)

    /// The upstream explicitly reported the video has been removed.
    case removed(SongID)

    /// The upstream explicitly reported the video is blocked in this region.
    case regionBlocked(SongID, region: String?)

    /// The upstream explicitly reported the video requires age verification.
    case ageRestricted(SongID)

    /// The source is a live stream, which this app does not support.
    case liveStreamUnsupported(SongID)

    /// The upstream returned no audio-only renditions for this video.
    /// Distinct from `notFound` — the video exists but has no usable audio.
    case noAudioRenditions(SongID)

    // ── Mechanism-side: our code no longer works. Maintainer-facing. Loud. ──
    // NEVER silently retry — retrying a broken parser burns quota.

    /// Our parser failed at a specific stage. The upstream said nothing about
    /// unavailability — this is a code/markup problem, not a content problem.
    /// Carrying `stage` lets a maintainer tell a markup change from a cipher
    /// change without a debugger.
    case resolutionFailed(SongID, stage: ResolutionStage, detail: String)

    /// Parsing succeeded structurally but produced impossible values.
    /// Louder than `resolutionFailed` — indicates the upstream contract changed.
    case upstreamContractChanged(detail: String)

    /// The cipher/signature solver failed.
    case cipherFailure(detail: String)

    // ── Environment: neither party is at fault. Retryable. ──

    /// No network connectivity.
    case offline

    /// A network call did not complete within the allowed time.
    case timeout(stage: ResolutionStage)

    /// The upstream is rate-limiting us.
    case rateLimited(retryAfter: TimeInterval?)

    /// The API quota is exhausted.
    case quotaExhausted(resetAt: Date?)

    /// The caller abandoned the request. Unlike `offline`, nothing is wrong:
    /// do not retry it and do not show it to the singer.
    case cancelled

    // ── Caller fault. ──

    /// The caller passed a reference that cannot be parsed to a SongID.
    /// No network call is made — this is a pure parse failure.
    case malformedReference(String)

    /// The caller requested an itag that is not in the rendition set.
    case unknownItag(SongID, itag: Int)
}

// MARK: - Classification helpers

extension SourceError {

    /// True for content-side errors. The router returns these immediately
    /// without trying the next provider — a private song is private everywhere.
    var isContentSide: Bool {
        switch self {
        case .notFound, .private_, .removed, .regionBlocked,
             .ageRestricted, .liveStreamUnsupported, .noAudioRenditions:
            return true
        default:
            return false
        }
    }

    /// True for mechanism-side errors. The router falls through to the next
    /// provider, but these are never silently retried.
    var isMechanismSide: Bool {
        switch self {
        case .resolutionFailed, .upstreamContractChanged, .cipherFailure:
            return true
        default:
            return false
        }
    }

    /// True for environment errors. The router falls through and these are
    /// eligible for automatic retry.
    var isEnvironment: Bool {
        switch self {
        case .offline, .timeout, .rateLimited, .quotaExhausted:
            return true
        default:
            return false
        }
    }

    /// True for caller-fault errors.
    var isCallerFault: Bool {
        switch self {
        case .malformedReference, .unknownItag:
            return true
        default:
            return false
        }
    }

    /// True when the router should fall through to the next provider.
    /// Content-side errors do NOT fall through — a private song is private
    /// for every provider. Cancellation does not fall through either: the
    /// caller walked away, so trying harder serves nobody.
    var shouldFallThrough: Bool {
        guard case .cancelled = self else {
            return isMechanismSide || isEnvironment
        }
        return false
    }
}
