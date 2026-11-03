import Foundation
import Testing
@testable import Karaoke
import YouTubeKit

// MARK: - ErrorClassificationTests
//
// The highest-value test in the project (contracts/source-provider.md).
//
// Tests the classification table: recorded upstream responses → correct SourceError case.
// The critical invariant: a broken parser (extractError, htmlParseError, regexMatchError)
// must NEVER be classified as notFound. Misclassifying mechanism failures as content-side
// errors hides breakage until the whole library appears empty.

@Suite("Error Classification — highest-value test")
struct ErrorClassificationTests {

    // MARK: - Content-side errors (upstream explicitly said unavailable)

    @Test("videoUnavailable → notFound (content-side)")
    func videoUnavailableIsNotFound() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.videoUnavailable, songID: "testSongID11", stage: .fetchingPage)
        if case .notFound(let id) = error {
            #expect(id == "testSongID11")
        } else {
            Issue.record("Expected notFound, got \(error)")
        }
        #expect(error.isContentSide)
        #expect(!error.isMechanismSide)
    }

    @Test("videoPrivate → private_ (content-side)")
    func videoPrivateIsPrivate() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.videoPrivate, songID: "testSongID11", stage: .fetchingPage)
        if case .private_(let id) = error {
            #expect(id == "testSongID11")
        } else {
            Issue.record("Expected private_, got \(error)")
        }
        #expect(error.isContentSide)
    }

    @Test("videoAgeRestricted → ageRestricted (content-side)")
    func videoAgeRestrictedIsAgeRestricted() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.videoAgeRestricted, songID: "testSongID11", stage: .fetchingPage)
        if case .ageRestricted(let id) = error {
            #expect(id == "testSongID11")
        } else {
            Issue.record("Expected ageRestricted, got \(error)")
        }
        #expect(error.isContentSide)
    }

    @Test("videoRegionBlocked → regionBlocked (content-side)")
    func videoRegionBlockedIsRegionBlocked() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.videoRegionBlocked, songID: "testSongID11", stage: .fetchingPage)
        if case .regionBlocked(let id, _) = error {
            #expect(id == "testSongID11")
        } else {
            Issue.record("Expected regionBlocked, got \(error)")
        }
        #expect(error.isContentSide)
    }

    @Test("liveStreamError → liveStreamUnsupported (content-side)")
    func liveStreamErrorIsLiveStreamUnsupported() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.liveStreamError, songID: "testSongID11", stage: .fetchingPage)
        if case .liveStreamUnsupported(let id) = error {
            #expect(id == "testSongID11")
        } else {
            Issue.record("Expected liveStreamUnsupported, got \(error)")
        }
        #expect(error.isContentSide)
    }

    @Test("membersOnly → private_ (content-side)")
    func membersOnlyIsPrivate() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.membersOnly, songID: "testSongID11", stage: .fetchingPage)
        if case .private_ = error {
            // correct
        } else {
            Issue.record("Expected private_, got \(error)")
        }
        #expect(error.isContentSide)
    }

    // MARK: - Mechanism-side errors (CRITICAL: must NOT be notFound)

    @Test("extractError → resolutionFailed NOT notFound (mechanism-side) — CRITICAL")
    func extractErrorIsResolutionFailedNotNotFound() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.extractError, songID: "testSongID11", stage: .parsingFormats)

        // The critical assertion: a broken parser must NEVER appear as notFound.
        if case .notFound = error {
            Issue.record("CRITICAL: extractError was classified as notFound. This hides parser breakage.")
        }

        if case .resolutionFailed(let id, _, _) = error {
            #expect(id == "testSongID11")
        } else {
            Issue.record("Expected resolutionFailed, got \(error)")
        }

        #expect(error.isMechanismSide)
        #expect(!error.isContentSide)
    }

    @Test("htmlParseError → resolutionFailed NOT notFound (mechanism-side) — CRITICAL")
    func htmlParseErrorIsResolutionFailedNotNotFound() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.htmlParseError, songID: "testSongID11", stage: .parsingPlayerResponse)

        if case .notFound = error {
            Issue.record("CRITICAL: htmlParseError was classified as notFound.")
        }

        if case .resolutionFailed(_, let stage, _) = error {
            #expect(stage == .parsingPlayerResponse)
        } else {
            Issue.record("Expected resolutionFailed, got \(error)")
        }

        #expect(error.isMechanismSide)
        #expect(!error.isContentSide)
    }

    @Test("regexMatchError → resolutionFailed NOT notFound (mechanism-side) — CRITICAL")
    func regexMatchErrorIsResolutionFailedNotNotFound() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.regexMatchError, songID: "testSongID11", stage: .extractingCipher)

        if case .notFound = error {
            Issue.record("CRITICAL: regexMatchError was classified as notFound.")
        }

        #expect(error.isMechanismSide)
        #expect(!error.isContentSide)
    }

    @Test("maxRetriesExceeded → resolutionFailed NOT notFound (mechanism-side)")
    func maxRetriesExceededIsResolutionFailed() {
        let provider = OnDeviceSourceProvider()
        let error = provider.testClassifyYouTubeKitError(.maxRetriesExceeded, songID: "testSongID11", stage: .fetchingPage)

        if case .notFound = error {
            Issue.record("CRITICAL: maxRetriesExceeded was classified as notFound.")
        }

        #expect(error.isMechanismSide)
        #expect(!error.isContentSide)
    }

    // MARK: - Environment errors

    @Test("URLError.notConnectedToInternet → offline (environment)")
    func notConnectedIsOffline() {
        let provider = OnDeviceSourceProvider()
        let urlError = URLError(.notConnectedToInternet)
        let error = provider.testClassifyURLError(urlError, stage: .fetchingPage)
        if case .offline = error {
            // correct
        } else {
            Issue.record("Expected offline, got \(error)")
        }
        #expect(error.isEnvironment)
        #expect(!error.isContentSide)
    }

    @Test("URLError.timedOut → timeout (environment)")
    func timedOutIsTimeout() {
        let provider = OnDeviceSourceProvider()
        let urlError = URLError(.timedOut)
        let error = provider.testClassifyURLError(urlError, stage: .fetchingPage)
        if case .timeout(let stage) = error {
            #expect(stage == .fetchingPage)
        } else {
            Issue.record("Expected timeout, got \(error)")
        }
        #expect(error.isEnvironment)
    }

    // MARK: - shouldFallThrough routing

    @Test("Content-side errors do NOT fall through")
    func contentSideDoesNotFallThrough() {
        let contentSideErrors: [SourceError] = [
            .notFound("testSongID11"),
            .private_("testSongID11"),
            .removed("testSongID11"),
            .regionBlocked("testSongID11", region: nil),
            .ageRestricted("testSongID11"),
            .liveStreamUnsupported("testSongID11"),
            .noAudioRenditions("testSongID11"),
        ]
        for error in contentSideErrors {
            #expect(!error.shouldFallThrough, "Content-side error \(error) should NOT fall through")
        }
    }

    @Test("Mechanism-side errors fall through")
    func mechanismSideFallsThrough() {
        let mechanismErrors: [SourceError] = [
            .resolutionFailed("testSongID11", stage: .fetchingPage, detail: "test"),
            .upstreamContractChanged(detail: "test"),
            .cipherFailure(detail: "test"),
        ]
        for error in mechanismErrors {
            #expect(error.shouldFallThrough, "Mechanism-side error \(error) should fall through")
        }
    }

    @Test("Environment errors fall through")
    func environmentFallsThrough() {
        let envErrors: [SourceError] = [
            .offline,
            .timeout(stage: .fetchingPage),
            .rateLimited(retryAfter: nil),
            .quotaExhausted(resetAt: nil),
        ]
        for error in envErrors {
            #expect(error.shouldFallThrough, "Environment error \(error) should fall through")
        }
    }
}

// MARK: - Test-only extension on OnDeviceSourceProvider

extension OnDeviceSourceProvider {
    func testClassifyYouTubeKitError(_ error: YouTubeKitError, songID: SongID, stage: ResolutionStage) -> SourceError {
        switch error {
        case .videoUnavailable:     return .notFound(songID)
        case .videoPrivate:         return .private_(songID)
        case .videoAgeRestricted:   return .ageRestricted(songID)
        case .videoRegionBlocked:   return .regionBlocked(songID, region: nil)
        case .liveStreamError:      return .liveStreamUnsupported(songID)
        case .membersOnly:          return .private_(songID)
        case .recordingUnavailable: return .removed(songID)
        case .extractError:         return .resolutionFailed(songID, stage: stage, detail: "extractError")
        case .htmlParseError:       return .resolutionFailed(songID, stage: .parsingPlayerResponse, detail: "htmlParseError")
        case .regexMatchError:      return .resolutionFailed(songID, stage: stage, detail: "regexMatchError")
        case .maxRetriesExceeded:   return .resolutionFailed(songID, stage: stage, detail: "maxRetriesExceeded")
        }
    }

    func testClassifyURLError(_ error: URLError, stage: ResolutionStage) -> SourceError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
        case .timedOut: return .timeout(stage: stage)
        default: return .resolutionFailed("unknown", stage: stage, detail: "URLError \(error.code.rawValue)")
        }
    }
}
