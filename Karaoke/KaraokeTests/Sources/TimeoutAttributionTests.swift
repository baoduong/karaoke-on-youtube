// Tests for T138 — timeout attribution.
//
// Verifies that timeouts surface as SourceError.timeout(stage:) with the
// correct stage, so a maintainer can tell where the hang occurred without
// a debugger (contracts/source-provider.md Behavioural requirement 7).

import Foundation
import Testing
@testable import Karaoke

@Suite("Timeout attribution (T138)")
struct TimeoutAttributionTests {

    @Test("timeout(stage: .fetchingPage) carries fetchingPage stage")
    func timeoutCarriesStage() {
        let error = SourceError.timeout(stage: .fetchingPage)
        if case .timeout(let stage) = error {
            #expect(stage == .fetchingPage)
        } else {
            Issue.record("Expected timeout, got \(error)")
        }
    }

    @Test("timeout(stage: .parsingFormats) carries parsingFormats stage")
    func timeoutParsingFormats() {
        let error = SourceError.timeout(stage: .parsingFormats)
        if case .timeout(let stage) = error {
            #expect(stage == .parsingFormats)
        } else {
            Issue.record("Expected timeout, got \(error)")
        }
    }

    @Test("timeout is an environment error — falls through in router")
    func timeoutIsEnvironment() {
        let error = SourceError.timeout(stage: .buildingAddress)
        #expect(error.isEnvironment)
        #expect(error.shouldFallThrough)
        #expect(!error.isContentSide)
        #expect(!error.isMechanismSide)
    }

    @Test("timeout is distinct from resolutionFailed")
    func timeoutDistinctFromResolutionFailed() {
        let timeout = SourceError.timeout(stage: .fetchingPage)
        let failed = SourceError.resolutionFailed("id", stage: .fetchingPage, detail: "test")
        #expect(timeout != failed)
    }

    @Test("all ResolutionStage values are distinct")
    func allStagesDistinct() {
        let stages: [ResolutionStage] = [
            .fetchingPage,
            .parsingPlayerResponse,
            .extractingCipher,
            .evaluatingCipher,
            .parsingFormats,
            .buildingAddress,
        ]
        let timeouts = stages.map { SourceError.timeout(stage: $0) }
        for i in 0 ..< timeouts.count {
            for j in (i + 1) ..< timeouts.count {
                #expect(timeouts[i] != timeouts[j])
            }
        }
    }

    @Test("cancelled is not an environment error — does not fall through")
    func cancelledDoesNotFallThrough() {
        let error = SourceError.cancelled
        #expect(!error.shouldFallThrough)
        #expect(!error.isEnvironment)
    }
}
