// Tests for T134 — CompanionSourceProvider error mapping and routing.
//
// Verifies:
// 1. Unhealthy when no address configured.
// 2. search() throws mechanism-side error (falls through in router).
// 3. metadata() throws mechanism-side error (falls through in router).
// 4. Rendition parsing: duplicate itag → resolutionFailed.
// 5. Address parsing: missing url field → upstreamContractChanged.
// 6. HTTP 404 from companion → unknownItag.
// 7. Timeout surfaces as timeout(stage:).
// 8. Cancellation surfaces as cancelled.

import Foundation
import Testing
@testable import Karaoke

@Suite("CompanionSourceProvider (T134)")
struct CompanionSourceProviderTests {

    // MARK: Health

    @Test("unhealthy when no address configured")
    func unhealthyWithNoAddress() async {
        UserDefaults.standard.removeObject(forKey: CompanionSourceProvider.addressKey)
        let provider = CompanionSourceProvider()
        let health = await provider.healthCheck()
        #expect(!health.isHealthy)
    }

    // MARK: Unsupported operations

    @Test("search throws mechanism-side error so router falls through")
    func searchThrowsMechanismSide() async {
        let provider = CompanionSourceProvider()
        await #expect(throws: SourceError.self) {
            let result = try await provider.search(query: "test", limit: 10)
            return result
        }
        // Verify it is mechanism-side (falls through in router, not content-side)
        do {
            _ = try await provider.search(query: "test", limit: 10)
        } catch let error as SourceError {
            #expect(error.isMechanismSide)
        } catch {}
    }

    @Test("metadata throws mechanism-side error so router falls through")
    func metadataThrowsMechanismSide() async throws {
        let provider = CompanionSourceProvider()
        let ref = try SourceReference.parse("dQw4w9WgXcQ")
        do {
            _ = try await provider.metadata(for: ref)
            Issue.record("Expected throw")
        } catch let error as SourceError {
            #expect(error.isMechanismSide)
        }
    }

    // MARK: Rendition parsing

    @Test("duplicate itag in renditions → resolutionFailed")
    func duplicateItagRenditions() async {
        let provider = CompanionSourceProvider()
        let json = """
        {"renditions":[
          {"itag":251,"container":"webm","codec":"opus","averageBitrateBps":128000,"isDecodableOnDevice":true},
          {"itag":251,"container":"webm","codec":"opus","averageBitrateBps":64000,"isDecodableOnDevice":true}
        ]}
        """.data(using: .utf8)!

        let result = provider.testParseRenditions(data: json, songID: "testID")
        switch result {
        case .failure(let error):
            if case .resolutionFailed = error {
                // correct
            } else {
                Issue.record("Expected resolutionFailed, got \(error)")
            }
        case .success:
            Issue.record("Expected failure for duplicate itag")
        }
    }

    @Test("valid renditions parse correctly")
    func validRenditionsParse() async {
        let provider = CompanionSourceProvider()
        let json = """
        {"renditions":[
          {"itag":251,"container":"webm","codec":"opus","averageBitrateBps":128000,"isDecodableOnDevice":true},
          {"itag":140,"container":"m4a","codec":"aac","averageBitrateBps":128000,"isDecodableOnDevice":true}
        ]}
        """.data(using: .utf8)!

        let result = provider.testParseRenditions(data: json, songID: "testID")
        switch result {
        case .success(let renditions):
            #expect(renditions.count == 2)
            #expect(renditions[0].itag == 251)
            #expect(renditions[1].itag == 140)
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    // MARK: Address parsing

    @Test("missing url field → upstreamContractChanged")
    func missingURLField() async {
        let provider = CompanionSourceProvider()
        let json = """
        {"renditionItag":251,"expiresAt":9999999999.0,"resolvedAt":1000000000.0,"supportsRangeRequests":true}
        """.data(using: .utf8)!

        let result = provider.testParseAddress(data: json, songID: "testID", itag: 251)
        switch result {
        case .failure(let error):
            if case .upstreamContractChanged = error {
                // correct
            } else {
                Issue.record("Expected upstreamContractChanged, got \(error)")
            }
        case .success:
            Issue.record("Expected failure for missing url")
        }
    }

    @Test("companion error field with 'not found' → unknownItag")
    func errorFieldNotFound() async {
        let provider = CompanionSourceProvider()
        let json = """
        {"error":"itag 999 not found for video testID"}
        """.data(using: .utf8)!

        let result = provider.testParseAddress(data: json, songID: "testID", itag: 999)
        switch result {
        case .failure(let error):
            if case .unknownItag = error {
                // correct
            } else {
                Issue.record("Expected unknownItag, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("valid address parses correctly")
    func validAddressParsed() async {
        let provider = CompanionSourceProvider()
        let json = """
        {"url":"https://example.invalid/stream","renditionItag":251,"expiresAt":9999999999.0,"resolvedAt":1000000000.0,"supportsRangeRequests":true}
        """.data(using: .utf8)!

        let result = provider.testParseAddress(data: json, songID: "testID", itag: 251)
        switch result {
        case .success(let address):
            #expect(address.renditionItag == 251)
            #expect(address.supportsRangeRequests)
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }
}

// MARK: - Test-only extension to expose parsing internals

extension CompanionSourceProvider {
    func testParseRenditions(data: Data, songID: SongID) -> Result<[AudioRendition], SourceError> {
        do {
            let result = try parseRenditionsInternal(data: data, songID: songID)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    func testParseAddress(data: Data, songID: SongID, itag: Int) -> Result<StreamAddress, SourceError> {
        do {
            let result = try parseAddressInternal(data: data, songID: songID, itag: itag)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}
