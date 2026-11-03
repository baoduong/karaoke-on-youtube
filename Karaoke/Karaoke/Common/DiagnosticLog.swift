// T035 — DiagnosticLog.
//
// Local diagnostic logging for mechanism-side errors. Records stage, timestamp,
// and a redacted detail string.
//
// INVARIANT: StreamAddress.url MUST NEVER appear in a log, an error message,
// or persistent storage (data-model invariant 4). This file enforces that by
// accepting only pre-redacted strings and by never accepting StreamAddress
// values directly.

import Foundation
import os.log

// MARK: - DiagnosticLog

/// Local diagnostic logging for mechanism-side errors.
///
/// Only mechanism-side errors are recorded — content-side errors are the
/// singer's problem, environment errors are transient. Mechanism-side errors
/// are the maintainer's signal that something is broken.
///
/// StreamAddress.url is excluded from every log entry. Callers must redact
/// URLs before passing detail strings.
enum DiagnosticLog {

    // MARK: OSLog subsystem

    private static let subsystem = "com.karaoke.personal"

    private static let mechanismLog = Logger(
        subsystem: subsystem,
        category: "mechanism"
    )

    private static let environmentLog = Logger(
        subsystem: subsystem,
        category: "environment"
    )

    private static let generalLog = Logger(
        subsystem: subsystem,
        category: "general"
    )

    // MARK: Public API

    /// Record a mechanism-side error.
    ///
    /// - Parameters:
    ///   - error: The SourceError (must be mechanism-side).
    ///   - songID: The song being resolved when the error occurred.
    ///   - providerID: Which provider encountered the error.
    ///
    /// StreamAddress.url must never appear in `detail` strings. This is
    /// enforced by the SourceError type — `resolutionFailed.detail` and
    /// `cipherFailure.detail` must be pre-redacted by the caller.
    static func recordMechanismError(
        _ error: SourceError,
        songID: SongID,
        providerID: SourceProviderID
    ) {
        guard error.isMechanismSide else { return }

        switch error {
        case .resolutionFailed(let id, let stage, let detail):
            mechanismLog.error(
                "resolutionFailed songID=\(id, privacy: .public) stage=\(String(describing: stage), privacy: .public) provider=\(providerID.rawValue, privacy: .public) detail=\(redact(detail), privacy: .public)"
            )

        case .upstreamContractChanged(let detail):
            mechanismLog.fault(
                "upstreamContractChanged songID=\(songID, privacy: .public) provider=\(providerID.rawValue, privacy: .public) detail=\(redact(detail), privacy: .public)"
            )

        case .cipherFailure(let detail):
            mechanismLog.error(
                "cipherFailure songID=\(songID, privacy: .public) provider=\(providerID.rawValue, privacy: .public) detail=\(redact(detail), privacy: .public)"
            )

        default:
            break
        }
    }

    /// Record an environment error (informational — these are retryable).
    static func recordEnvironmentError(
        _ error: SourceError,
        songID: SongID,
        providerID: SourceProviderID
    ) {
        guard error.isEnvironment else { return }

        switch error {
        case .offline:
            environmentLog.info(
                "offline songID=\(songID, privacy: .public) provider=\(providerID.rawValue, privacy: .public)"
            )

        case .timeout(let stage):
            environmentLog.warning(
                "timeout songID=\(songID, privacy: .public) stage=\(String(describing: stage), privacy: .public) provider=\(providerID.rawValue, privacy: .public)"
            )

        case .rateLimited(let retryAfter):
            let retryStr = retryAfter.map { String($0) } ?? "unknown"
            environmentLog.warning(
                "rateLimited songID=\(songID, privacy: .public) retryAfter=\(retryStr, privacy: .public) provider=\(providerID.rawValue, privacy: .public)"
            )

        case .quotaExhausted(let resetAt):
            let resetStr = resetAt.map { $0.description } ?? "unknown"
            environmentLog.warning(
                "quotaExhausted songID=\(songID, privacy: .public) resetAt=\(resetStr, privacy: .public) provider=\(providerID.rawValue, privacy: .public)"
            )

        default:
            break
        }
    }

    /// Record a provider health change.
    static func recordHealthChange(
        providerID: SourceProviderID,
        health: ProviderHealth
    ) {
        switch health {
        case .healthy:
            generalLog.info("provider=\(providerID.rawValue, privacy: .public) health=healthy")
        case .unhealthy(let reason):
            generalLog.warning(
                "provider=\(providerID.rawValue, privacy: .public) health=unhealthy reason=\(redact(reason), privacy: .public)"
            )
        }
    }

    /// Record which provider served a request (FR-005 attribution).
    static func recordServedBy(
        providerID: SourceProviderID,
        songID: SongID,
        operation: String
    ) {
        generalLog.info(
            "served songID=\(songID, privacy: .public) operation=\(operation, privacy: .public) provider=\(providerID.rawValue, privacy: .public)"
        )
    }

    // MARK: URL redaction

    /// Redact a string that might contain a URL.
    ///
    /// Removes any substring that looks like a URL with a host component,
    /// replacing it with `[redacted-url]`. This is the enforcement mechanism
    /// for data-model invariant 4: StreamAddress.url must never appear in a log.
    static func redact(_ detail: String) -> String {
        // Pattern: anything that looks like https://... or http://...
        // We replace the entire URL to avoid leaking path components that
        // might contain signed parameters.
        var result = detail
        if let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#,
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "[redacted-url]"
            )
        }
        return result
    }

    /// Verify that a string contains no URL-like content.
    /// Used in tests to assert the invariant.
    static func containsURL(_ string: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#,
            options: []
        ) else { return false }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
}
