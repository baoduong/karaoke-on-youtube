import Foundation

// MARK: - SourceProviderRouter

/// Routes requests across multiple SourceProvider implementations.
///
/// Routing rules (contracts/source-provider.md):
/// - Providers are tried in order.
/// - Unhealthy providers are skipped.
/// - Content-side errors return IMMEDIATELY — a private song is private for
///   every provider; trying again wastes time.
/// - Mechanism-side and environment errors fall through to the next provider.
/// - The identifier of the serving provider is recorded for FR-005 attribution.
actor SourceProviderRouter: SourceProvider {

    let identifier = SourceProviderID(rawValue: "router")

    private let providers: [any SourceProvider]

    /// The provider that served the most recent successful request.
    private(set) var lastServingProviderID: SourceProviderID?

    init(ordered providers: [any SourceProvider]) {
        self.providers = providers
    }

    // MARK: SourceProvider

    func healthCheck() async -> ProviderHealth {
        for provider in providers {
            let health = await provider.healthCheck()
            if health.isHealthy { return .healthy }
        }
        return .unhealthy(reason: "all providers unhealthy")
    }

    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata] {
        var lastError: SourceError = .offline
        for provider in providers {
            guard await provider.healthCheck().isHealthy else { continue }
            do {
                let results = try await provider.search(query: query, limit: limit)
                lastServingProviderID = provider.identifier
                DiagnosticLog.recordServedBy(providerID: provider.identifier, songID: "search", operation: "search")
                return results
            } catch {
                lastError = error
                if error.isContentSide { throw error }
                DiagnosticLog.recordMechanismError(error, songID: "search", providerID: provider.identifier)
            }
        }
        throw lastError
    }

    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata {
        var lastError: SourceError = .offline
        for provider in providers {
            guard await provider.healthCheck().isHealthy else { continue }
            do {
                let result = try await provider.metadata(for: reference)
                lastServingProviderID = provider.identifier
                DiagnosticLog.recordServedBy(providerID: provider.identifier, songID: reference.songID, operation: "metadata")
                return result
            } catch {
                lastError = error
                if error.isContentSide { throw error }
                DiagnosticLog.recordMechanismError(error, songID: reference.songID, providerID: provider.identifier)
            }
        }
        throw lastError
    }

    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition] {
        var lastError: SourceError = .offline
        for provider in providers {
            guard await provider.healthCheck().isHealthy else { continue }
            do {
                let result = try await provider.audioRenditions(for: songID)
                lastServingProviderID = provider.identifier
                DiagnosticLog.recordServedBy(providerID: provider.identifier, songID: songID, operation: "audioRenditions")
                return result
            } catch {
                lastError = error
                if error.isContentSide { throw error }
                DiagnosticLog.recordMechanismError(error, songID: songID, providerID: provider.identifier)
            }
        }
        throw lastError
    }

    func streamAddress(for songID: SongID, itag: Int) async throws(SourceError) -> StreamAddress {
        var lastError: SourceError = .offline
        for provider in providers {
            guard await provider.healthCheck().isHealthy else { continue }
            do {
                let result = try await provider.streamAddress(for: songID, itag: itag)
                lastServingProviderID = provider.identifier
                DiagnosticLog.recordServedBy(providerID: provider.identifier, songID: songID, operation: "streamAddress")
                return result
            } catch {
                lastError = error
                if error.isContentSide { throw error }
                DiagnosticLog.recordMechanismError(error, songID: songID, providerID: provider.identifier)
            }
        }
        throw lastError
    }
}
