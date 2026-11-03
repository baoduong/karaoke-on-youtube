import Foundation
import Testing
@testable import Karaoke

// MARK: - Mock providers for router tests

private final class MockProvider: SourceProvider, @unchecked Sendable {
    let identifier: SourceProviderID
    let health: ProviderHealth
    let searchResult: Result<[SongMetadata], SourceError>
    let metadataResult: Result<SongMetadata, SourceError>
    let renditionsResult: Result<[AudioRendition], SourceError>
    let streamAddressResult: Result<StreamAddress, SourceError>

    private(set) var callCount = 0

    init(
        id: String,
        health: ProviderHealth = .healthy,
        searchResult: Result<[SongMetadata], SourceError> = .success([]),
        metadataResult: Result<SongMetadata, SourceError> = .success(MockProvider.defaultMeta),
        renditionsResult: Result<[AudioRendition], SourceError> = .success([]),
        streamAddressResult: Result<StreamAddress, SourceError> = .success(MockProvider.defaultAddress)
    ) {
        self.identifier = SourceProviderID(rawValue: id)
        self.health = health
        self.searchResult = searchResult
        self.metadataResult = metadataResult
        self.renditionsResult = renditionsResult
        self.streamAddressResult = streamAddressResult
    }

    static let defaultMeta = SongMetadata(id: "testSongID11", title: "Test", channelName: "Ch", durationSeconds: 180, thumbnailURL: nil)
    static let defaultAddress = StreamAddress(
        url: URL(string: "https://example.invalid/stream")!,
        renditionItag: 140,
        expiresAt: Date().addingTimeInterval(3600),
        resolvedAt: Date(),
        supportsRangeRequests: true
    )

    func healthCheck() async -> ProviderHealth { health }

    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata] {
        switch searchResult {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }

    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata {
        switch metadataResult {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }

    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition] {
        switch renditionsResult {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }

    func streamAddress(for songID: SongID, itag: Int) async throws(SourceError) -> StreamAddress {
        switch streamAddressResult {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}

// MARK: - Router tests

@Suite("SourceProviderRouter")
struct SourceProviderRouterTests {

    private func makeRef() throws -> SourceReference {
        try SourceReference.parse("dQw4w9WgXcQ")
    }

    // MARK: - Content-side errors stop the chain

    @Test("Content-side error stops chain — notFound")
    func contentSideStopsChain() async throws {
        let first = MockProvider(id: "first", metadataResult: .failure(.notFound("dQw4w9WgXcQ")))
        let second = MockProvider(id: "second", metadataResult: .success(MockProvider.defaultMeta))
        let router = SourceProviderRouter(ordered: [first, second])

        let ref = try makeRef()
        await #expect(throws: SourceError.notFound("dQw4w9WgXcQ")) {
            try await router.metadata(for: ref)
        }
    }

    @Test("Content-side error stops chain — private_")
    func privateStopsChain() async throws {
        let first = MockProvider(id: "first", renditionsResult: .failure(.private_("dQw4w9WgXcQ")))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        await #expect(throws: SourceError.private_("dQw4w9WgXcQ")) {
            try await router.audioRenditions(for: "dQw4w9WgXcQ")
        }
    }

    @Test("Content-side error stops chain — ageRestricted")
    func ageRestrictedStopsChain() async throws {
        let first = MockProvider(id: "first", renditionsResult: .failure(.ageRestricted("dQw4w9WgXcQ")))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        await #expect(throws: SourceError.ageRestricted("dQw4w9WgXcQ")) {
            try await router.audioRenditions(for: "dQw4w9WgXcQ")
        }
    }

    // MARK: - Mechanism-side errors fall through

    @Test("Mechanism-side error falls through to next provider")
    func mechanismSideFallsThrough() async throws {
        let first = MockProvider(
            id: "first",
            renditionsResult: .failure(.resolutionFailed("dQw4w9WgXcQ", stage: .parsingFormats, detail: "test"))
        )
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        let result = try await router.audioRenditions(for: "dQw4w9WgXcQ")
        #expect(result.isEmpty)

        let servingID = await router.lastServingProviderID
        #expect(servingID?.rawValue == "second")
    }

    @Test("cipherFailure falls through to next provider")
    func cipherFailureFallsThrough() async throws {
        let first = MockProvider(
            id: "first",
            renditionsResult: .failure(.cipherFailure(detail: "test"))
        )
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        let result = try await router.audioRenditions(for: "dQw4w9WgXcQ")
        #expect(result.isEmpty)
    }

    // MARK: - Environment errors fall through

    @Test("offline error falls through to next provider")
    func offlineFallsThrough() async throws {
        let first = MockProvider(id: "first", renditionsResult: .failure(.offline))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        let result = try await router.audioRenditions(for: "dQw4w9WgXcQ")
        #expect(result.isEmpty)
    }

    @Test("timeout falls through to next provider")
    func timeoutFallsThrough() async throws {
        let first = MockProvider(id: "first", renditionsResult: .failure(.timeout(stage: .fetchingPage)))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        let result = try await router.audioRenditions(for: "dQw4w9WgXcQ")
        #expect(result.isEmpty)
    }

    // MARK: - Unhealthy providers are skipped

    @Test("Unhealthy provider is skipped")
    func unhealthyProviderSkipped() async throws {
        let first = MockProvider(id: "first", health: .unhealthy(reason: "broken"))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        let result = try await router.audioRenditions(for: "dQw4w9WgXcQ")
        #expect(result.isEmpty)

        let servingID = await router.lastServingProviderID
        #expect(servingID?.rawValue == "second")
    }

    @Test("All unhealthy providers → last error propagated")
    func allUnhealthyPropagate() async {
        let first = MockProvider(id: "first", health: .unhealthy(reason: "broken"))
        let second = MockProvider(id: "second", health: .unhealthy(reason: "also broken"))
        let router = SourceProviderRouter(ordered: [first, second])

        await #expect(throws: SourceError.offline) {
            try await router.audioRenditions(for: "dQw4w9WgXcQ")
        }
    }

    // MARK: - Attribution

    @Test("Serving provider is attributed correctly")
    func servingProviderAttributed() async throws {
        let first = MockProvider(id: "first", renditionsResult: .failure(.offline))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        _ = try await router.audioRenditions(for: "dQw4w9WgXcQ")

        let servingID = await router.lastServingProviderID
        #expect(servingID?.rawValue == "second")
    }

    @Test("First provider success is attributed to first")
    func firstProviderAttributed() async throws {
        let first = MockProvider(id: "first", renditionsResult: .success([]))
        let second = MockProvider(id: "second", renditionsResult: .success([]))
        let router = SourceProviderRouter(ordered: [first, second])

        _ = try await router.audioRenditions(for: "dQw4w9WgXcQ")

        let servingID = await router.lastServingProviderID
        #expect(servingID?.rawValue == "first")
    }

    // MARK: - Router health

    @Test("Router is healthy when at least one provider is healthy")
    func routerHealthyWhenOneHealthy() async {
        let first = MockProvider(id: "first", health: .unhealthy(reason: "broken"))
        let second = MockProvider(id: "second", health: .healthy)
        let router = SourceProviderRouter(ordered: [first, second])

        let health = await router.healthCheck()
        #expect(health.isHealthy)
    }

    @Test("Router is unhealthy when all providers are unhealthy")
    func routerUnhealthyWhenAllUnhealthy() async {
        let first = MockProvider(id: "first", health: .unhealthy(reason: "broken"))
        let second = MockProvider(id: "second", health: .unhealthy(reason: "also broken"))
        let router = SourceProviderRouter(ordered: [first, second])

        let health = await router.healthCheck()
        #expect(!health.isHealthy)
    }
}
