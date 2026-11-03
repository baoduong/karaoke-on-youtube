// Tests for T125 — offline-vs-unsaved error selection.
//
// Verifies that PlaybackError correctly distinguishes:
// - .offline: network error, song may or may not be saved
// - .offlineUnsaved: no network AND song has no local copy
//
// The distinction matters: .offlineUnsaved tells the singer to save the song
// first; .offline tells them to check their connection.

import Foundation
import Testing
@testable import Karaoke

@Suite("Offline vs unsaved error selection (T125)")
struct OfflineUnsavedTests {

    @Test("PlaybackError.from(sourceError: .offline) → .offline")
    func offlineSourceError() {
        let error = PlaybackError.from(sourceError: .offline)
        #expect(error == .offline)
    }

    @Test("PlaybackError.offlineUnsaved() → .offlineUnsaved")
    func offlineUnsavedFactory() {
        let error = PlaybackError.offlineUnsaved()
        #expect(error == .offlineUnsaved)
    }

    @Test(".offline and .offlineUnsaved are distinct cases")
    func offlineAndOfflineUnsavedAreDistinct() {
        let offline = PlaybackError.offline
        let offlineUnsaved = PlaybackError.offlineUnsaved
        #expect(offline != offlineUnsaved)
    }

    @Test("content-side errors map to contentUnavailable, not offline")
    func contentSideNotOffline() {
        let cases: [SourceError] = [
            .notFound("id"),
            .private_("id"),
            .removed("id"),
            .ageRestricted("id"),
            .liveStreamUnsupported("id"),
            .noAudioRenditions("id"),
        ]
        for sourceError in cases {
            let playbackError = PlaybackError.from(sourceError: sourceError)
            if case .contentUnavailable = playbackError {
                // correct
            } else {
                Issue.record("Expected contentUnavailable for \(sourceError), got \(playbackError)")
            }
        }
    }

    @Test("mechanism-side errors map to mechanismFailed")
    func mechanismSideMapsToMechanismFailed() {
        let cases: [SourceError] = [
            .resolutionFailed("id", stage: .parsingFormats, detail: "test"),
            .upstreamContractChanged(detail: "test"),
            .cipherFailure(detail: "test"),
        ]
        for sourceError in cases {
            let playbackError = PlaybackError.from(sourceError: sourceError)
            if case .mechanismFailed = playbackError {
                // correct
            } else {
                Issue.record("Expected mechanismFailed for \(sourceError), got \(playbackError)")
            }
        }
    }

    @Test("timeout error maps to mechanismFailed (not offline)")
    func timeoutMapsToMechanismFailed() {
        let error = PlaybackError.from(sourceError: .timeout(stage: .fetchingPage))
        if case .mechanismFailed = error {
            // correct
        } else {
            Issue.record("Expected mechanismFailed for timeout, got \(error)")
        }
    }
}
