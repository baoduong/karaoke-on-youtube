import Testing
@testable import Karaoke
import Foundation

@Suite("StreamAddress Expiry Parsing")
struct StreamAddressTests {

    // MARK: - Expiry parsing

    @Test("URL with explicit expire parameter parses correctly")
    func explicitExpireParam() {
        let futureTimestamp: TimeInterval = 9_999_999_999
        let url = URL(string: "https://example.invalid/stream?expire=\(Int(futureTimestamp))&itag=140")!
        let expiry = StreamAddress.parseExpiry(from: url)
        let expected = Date(timeIntervalSince1970: futureTimestamp)
        #expect(abs(expiry.timeIntervalSince(expected)) < 1.0)
    }

    @Test("URL without expire parameter defaults conservatively")
    func noExpireParamDefaultsConservatively() {
        let url = URL(string: "https://example.invalid/stream?itag=140")!
        let before = Date()
        let expiry = StreamAddress.parseExpiry(from: url)
        let after = Date()

        // Conservative default is 5 minutes from now.
        let minExpected = before.addingTimeInterval(299)
        let maxExpected = after.addingTimeInterval(301)

        #expect(expiry >= minExpected, "Default expiry should be at least 5 minutes from now")
        #expect(expiry <= maxExpected, "Default expiry should be at most 5 minutes from now")
    }

    @Test("URL with non-numeric expire value defaults conservatively")
    func malformedExpireDefaultsConservatively() {
        let url = URL(string: "https://example.invalid/stream?expire=notanumber&itag=140")!
        let before = Date()
        let expiry = StreamAddress.parseExpiry(from: url)
        let after = Date()

        let minExpected = before.addingTimeInterval(299)
        let maxExpected = after.addingTimeInterval(301)

        #expect(expiry >= minExpected)
        #expect(expiry <= maxExpected)
    }

    @Test("URL with empty expire value defaults conservatively")
    func emptyExpireDefaultsConservatively() {
        let url = URL(string: "https://example.invalid/stream?expire=&itag=140")!
        let before = Date()
        let expiry = StreamAddress.parseExpiry(from: url)
        let after = Date()

        #expect(expiry >= before.addingTimeInterval(299))
        #expect(expiry <= after.addingTimeInterval(301))
    }

    // MARK: - Staleness

    @Test("Non-stale address is not stale")
    func nonStaleAddress() {
        let address = StreamAddress(
            url: URL(string: "https://example.invalid/stream")!,
            renditionItag: 140,
            expiresAt: Date().addingTimeInterval(3600),
            resolvedAt: Date(),
            supportsRangeRequests: true
        )
        #expect(!address.isStale)
        #expect(!address.isExpired)
    }

    @Test("Address within safety margin is stale")
    func addressWithinSafetyMarginIsStale() {
        let address = StreamAddress(
            url: URL(string: "https://example.invalid/stream")!,
            renditionItag: 140,
            expiresAt: Date().addingTimeInterval(StreamAddress.safetyMargin - 1),
            resolvedAt: Date(),
            supportsRangeRequests: true
        )
        #expect(address.isStale)
    }

    @Test("Expired address is stale and expired")
    func expiredAddressIsStaleAndExpired() {
        let address = StreamAddress(
            url: URL(string: "https://example.invalid/stream")!,
            renditionItag: 140,
            expiresAt: Date().addingTimeInterval(-1),
            resolvedAt: Date().addingTimeInterval(-3600),
            supportsRangeRequests: true
        )
        #expect(address.isStale)
        #expect(address.isExpired)
    }

    @Test("Safety margin is positive")
    func safetyMarginIsPositive() {
        #expect(StreamAddress.safetyMargin > 0)
    }

    // MARK: - Range request support

    @Test("parseSupportsRangeRequests returns true for YouTube-like URLs")
    func supportsRangeRequests() {
        let url = URL(string: "https://rr1---sn-example.googlevideo.com/videoplayback?expire=9999999999&itag=140")!
        let supports = StreamAddress.parseSupportsRangeRequests(from: url)
        #expect(supports)
    }

    // MARK: - URL never in logs (invariant 4)

    @Test("DiagnosticLog.redact removes URLs from detail strings")
    func urlRedactedFromLogs() {
        let detail = "Failed at https://rr1---sn-example.googlevideo.com/videoplayback?expire=123&sig=abc"
        let redacted = DiagnosticLog.redact(detail)
        #expect(!DiagnosticLog.containsURL(redacted), "URL must be redacted from log detail")
        #expect(redacted.contains("[redacted-url]"))
    }

    @Test("DiagnosticLog.containsURL detects URLs")
    func containsURLDetectsURLs() {
        #expect(DiagnosticLog.containsURL("see https://example.com for details"))
        #expect(!DiagnosticLog.containsURL("no url here"))
    }
}
