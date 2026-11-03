// T062 — AudioSessionController tests.
//
// Asserts that the session category is .playback on every path through `prepare`.
// This test is what keeps FR-010 true as the code changes — if someone adds a
// conditional that could configure .playAndRecord, this test catches it.
//
// Satisfies: FR-010, SC-003

import Testing
import AVFoundation
@testable import Karaoke

@Suite("AudioSessionController")
struct AudioSessionControllerTests {

    // MARK: Category invariant

    /// The session category must be .playback after prepare().
    ///
    /// This is the test that enforces FR-010: no code path may configure
    /// .playAndRecord. If this test fails, the microphone invariant is broken.
    @Test("prepare() sets category to .playback")
    func prepareSetsPlaybackCategory() throws {
        let controller = AudioSessionController()
        try controller.prepare()
        #expect(controller.currentCategory == .playback)
    }

    /// Category options must be empty.
    ///
    /// Regression test. `.defaultToSpeaker` was passed alongside `.playback`,
    /// which is only legal with `.playAndRecord`. A device rejects the whole
    /// call with OSStatus -50, leaving the session unconfigured and the music
    /// on the iPhone's own speaker instead of the PA — while the simulator
    /// accepted it silently and every other test here stayed green.
    ///
    /// Asserting the category alone could not catch that; asserting the
    /// options can, on any platform.
    @Test("prepare() sets no category options")
    func prepareSetsNoCategoryOptions() throws {
        let controller = AudioSessionController()
        try controller.prepare()
        #expect(controller.currentCategoryOptions.isEmpty)
    }

    /// Calling prepare() multiple times must not change the category.
    @Test("prepare() is idempotent — category stays .playback")
    func prepareIsIdempotent() throws {
        let controller = AudioSessionController()
        try controller.prepare()
        try controller.prepare()
        #expect(controller.currentCategory == .playback)
    }

    /// The category must never be .playAndRecord.
    ///
    /// .playAndRecord would prompt for microphone access (FR-010 violation) and
    /// can force Bluetooth to HFP profile, which is telephone-quality mono.
    @Test("category is never .playAndRecord")
    func categoryIsNeverPlayAndRecord() throws {
        let controller = AudioSessionController()
        try controller.prepare()
        #expect(controller.currentCategory != .record)
        #expect(controller.currentCategory != .playAndRecord)
        #expect(controller.currentCategory != .multiRoute)
    }

    /// After deactivate(), prepare() must still set .playback.
    @Test("prepare() after deactivate() still sets .playback")
    func prepareAfterDeactivate() throws {
        let controller = AudioSessionController()
        try controller.prepare()
        controller.deactivate()
        try controller.prepare()
        #expect(controller.currentCategory == .playback)
    }
}
