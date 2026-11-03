// T067 — Seek bounds tests.
//
// Asserts that out-of-range seeks yield seekOutOfBounds rather than clamping
// silently. Silent clamping hides bugs in callers that compute positions
// incorrectly (audio-pipeline.md Test contract).
//
// Satisfies: FR-023, audio-pipeline.md Behavioural requirement 4

import Testing
@testable import Karaoke

@Suite("Seek bounds")
struct SeekTests {

    // MARK: AudioError.seekOutOfBounds

    /// seekOutOfBounds carries the requested position and the duration.
    @Test("seekOutOfBounds carries requested and duration")
    func seekOutOfBoundsCarriesValues() {
        let error = AudioError.seekOutOfBounds(requested: 120.0, duration: 90.0)
        if case .seekOutOfBounds(let requested, let duration) = error {
            #expect(requested == 120.0)
            #expect(duration == 90.0)
        } else {
            Issue.record("Expected seekOutOfBounds")
        }
    }

    /// seekOutOfBounds is distinct from sourceUnreadable.
    @Test("seekOutOfBounds is not sourceUnreadable")
    func seekOutOfBoundsIsDistinct() {
        let error = AudioError.seekOutOfBounds(requested: 120.0, duration: 90.0)
        var isSourceUnreadable = false
        if case .sourceUnreadable = error { isSourceUnreadable = true }
        #expect(isSourceUnreadable == false)
    }

    // MARK: PlayerPipeline seek bounds

    /// Seeking past the end of the asset yields seekOutOfBounds.
    @MainActor
    @Test("seek past end yields seekOutOfBounds")
    func seekPastEndYieldsError() async {
        let pipeline = PlayerPipeline()
        // No item loaded — duration is 0, so any positive seek is out of bounds.
        do {
            try await pipeline.seek(to: 10.0)
            Issue.record("Expected seekOutOfBounds to be thrown")
        } catch AudioError.seekOutOfBounds(let requested, let duration) {
            #expect(requested == 10.0)
            #expect(duration == 0.0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// Seeking to a negative position yields seekOutOfBounds.
    @MainActor
    @Test("seek to negative position yields seekOutOfBounds")
    func seekNegativeYieldsError() async {
        let pipeline = PlayerPipeline()
        do {
            try await pipeline.seek(to: -1.0)
            Issue.record("Expected seekOutOfBounds to be thrown")
        } catch AudioError.seekOutOfBounds(let requested, _) {
            #expect(requested == -1.0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// Seeking to 0.0 with no item loaded yields seekOutOfBounds (duration is 0).
    @MainActor
    @Test("seek to 0 with no item yields seekOutOfBounds")
    func seekZeroNoItemYieldsError() async {
        let pipeline = PlayerPipeline()
        do {
            try await pipeline.seek(to: 0.0)
            Issue.record("Expected seekOutOfBounds to be thrown")
        } catch AudioError.seekOutOfBounds {
            // Correct — no item loaded, duration is 0.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: PlaybackError from AudioError

    /// PlaybackError.from(audioError:) maps seekOutOfBounds correctly.
    @Test("PlaybackError maps seekOutOfBounds to audioError")
    func playbackErrorMapsSeekOutOfBounds() {
        let audioError = AudioError.seekOutOfBounds(requested: 200.0, duration: 180.0)
        let playbackError = PlaybackError.from(audioError: audioError)
        if case .audioError(let detail) = playbackError {
            #expect(detail.contains("200"))
            #expect(detail.contains("180"))
        } else {
            Issue.record("Expected .audioError")
        }
    }
}
