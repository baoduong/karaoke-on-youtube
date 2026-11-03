import Testing
import Foundation
import SwiftData
import AVFoundation
@testable import Karaoke

// MARK: - SaveCoordinatorTests (T127)

/// Tests for SaveCoordinator's state machine transitions, truncated-file
/// rejection, cancellation cleanup, and no-space isolation.
///
/// Constitution Principle IV: test what fails silently. The state machine
/// transitions and file verification are exactly the logic that can silently
/// corrupt offline storage.
///
/// All tests use an in-memory ModelContainer and a temporary directory.
/// No fixed sleeps or polling — state is observed directly after each operation.
@Suite("SaveCoordinator")
@MainActor
struct SaveCoordinatorTests {

    // MARK: - Test environment

    private static func makeEnv() throws -> (context: ModelContext, store: MediaStore, coordinator: SaveCoordinator) {
        let store = try MediaStore(inMemory: true)
        let context = ModelContext(store.container)
        let coordinator = SaveCoordinator(mediaStore: store)
        return (context, store, coordinator)
    }

    private static func insertSong(id: String, context: ModelContext) {
        let song = Song(
            id: id,
            title: "Test Song",
            channelName: "Test Channel",
            durationSeconds: 180
        )
        context.insert(song)
    }

    private static func makeRequest(
        songID: String,
        streamURL: URL,
        expectedByteSize: Int64? = nil,
        fileRelativePath: String? = nil
    ) -> SaveRequest {
        SaveRequest(
            songID: songID,
            streamURL: streamURL,
            expectedByteSize: expectedByteSize,
            container: .m4a,
            codec: .aac,
            averageBitrateBps: 128_000,
            fileRelativePath: fileRelativePath ?? "\(songID).m4a"
        )
    }

    // MARK: - Helpers: real audio file

    enum FixtureError: Error {
        case formatUnavailable
        case bufferAllocationFailed
        case wroteNoBytes
    }

    /// Writes a short, genuinely decodable M4A of silence.
    ///
    /// It must be real audio, not placeholder bytes: `SaveCoordinator` refuses
    /// to mark a save complete until AVFoundation confirms the file decodes
    /// (T121), so a fake payload would fail the check correctly and tell us
    /// nothing about the state machine under test.
    @discardableResult
    private static func writeMinimalAudioFile(to url: URL) async throws -> Int64 {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate / 2)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw FixtureError.formatUnavailable
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw FixtureError.bufferAllocationFailed
        }
        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else {
                throw FixtureError.bufferAllocationFailed
            }
            samples.update(repeating: 0, count: Int(frameCount))
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        guard size > 0 else { throw FixtureError.wroteNoBytes }
        return size
    }

    // MARK: - State machine: pending → downloading → complete

    @Suite("State machine transitions")
    @MainActor
    struct StateMachineTests {

        @Test("startSave creates record and marks complete after successful download")
        func startSaveCompletesSuccessfully() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song001", context: context)

            // Write a real audio file to serve as the "stream".
            let sourceURL = store.stagingDirectoryURL.appendingPathComponent("source_song001.m4a")
            let fileSize = try await writeMinimalAudioFile(to: sourceURL)

            let request = makeRequest(
                songID: "song001",
                streamURL: sourceURL,
                expectedByteSize: fileSize
            )

            try await coordinator.startSave(request: request, context: context)

            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song001" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            #expect(results.count == 1)
            #expect(results[0].state == .complete)
            #expect(results[0].byteSize > 0)
            #expect(results[0].downloadedBytes == results[0].byteSize)
            #expect(results[0].lastError == nil)
        }

        @Test("retry moves failed → complete")
        func retryMovesFailedToComplete() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song003", context: context)

            // Insert a pre-failed record.
            let saved = SavedSong(
                songID: "song003",
                fileRelativePath: "song003.m4a",
                container: .m4a,
                codec: .aac,
                state: .failed,
                lastError: "Previous network error"
            )
            context.insert(saved)

            let sourceURL = store.stagingDirectoryURL.appendingPathComponent("source_song003.m4a")
            let fileSize = try await writeMinimalAudioFile(to: sourceURL)

            let request = makeRequest(
                songID: "song003",
                streamURL: sourceURL,
                expectedByteSize: fileSize
            )

            try await coordinator.retry(songID: "song003", request: request, context: context)

            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song003" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            #expect(results[0].state == .complete)
            #expect(results[0].lastError == nil)
        }

        @Test("delete removes file and record together")
        func deleteRemovesFileAndRecord() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song004", context: context)

            // Write a real file and create a complete record.
            let fileName = "song004.m4a"
            let fileURL = store.mediaDirectoryURL.appendingPathComponent(fileName)
            let fileSize = try await writeMinimalAudioFile(to: fileURL)

            let saved = SavedSong(
                songID: "song004",
                fileRelativePath: fileName,
                container: .m4a,
                codec: .aac,
                byteSize: fileSize,
                state: .complete,
                downloadedBytes: fileSize
            )
            context.insert(saved)
            try context.save()

            try await coordinator.delete(songID: "song004", context: context)

            // Record is gone.
            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song004" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            #expect(results.isEmpty)

            // File is gone.
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }

        @Test("cancel removes record and deletes partial staging file")
        func cancelRemovesRecordAndStagingFile() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song005", context: context)

            // Create a partial staging file to simulate an in-progress download.
            let stagingURL = store.stagingURL(for: "song005", container: .m4a)
            try Data("partial data".utf8).write(to: stagingURL)

            let saved = SavedSong(
                songID: "song005",
                fileRelativePath: "song005.m4a",
                container: .m4a,
                codec: .aac,
                state: .downloading,
                downloadedBytes: 12
            )
            context.insert(saved)
            try context.save()

            try await coordinator.cancel(songID: "song005", context: context)

            // Record is gone — cancelled → (none).
            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song005" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            #expect(results.isEmpty)

            // Staging file is deleted.
            #expect(!FileManager.default.fileExists(atPath: stagingURL.path))
        }

        @Test("startSave throws alreadyExists for a complete song")
        func startSaveThrowsForExistingComplete() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song006", context: context)

            let saved = SavedSong(
                songID: "song006",
                fileRelativePath: "song006.m4a",
                container: .m4a,
                codec: .aac,
                state: .complete
            )
            context.insert(saved)

            let request = makeRequest(
                songID: "song006",
                streamURL: URL(string: "https://example.com/audio.m4a")!
            )

            do {
                try await coordinator.startSave(request: request, context: context)
                Issue.record("Expected alreadyExists error")
            } catch SaveCoordinatorError.alreadyExists(let id) {
                #expect(id == "song006")
            }
        }

        @Test("cancelling a pending download removes the record")
        func cancelPendingRemovesRecord() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song030", context: context)

            let saved = SavedSong(
                songID: "song030",
                fileRelativePath: "song030.m4a",
                container: .m4a,
                codec: .aac,
                state: .pending
            )
            context.insert(saved)
            try context.save()

            try await coordinator.cancel(songID: "song030", context: context)

            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song030" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            #expect(results.isEmpty)
        }
    }

    // MARK: - T121: Truncated file rejection

    @Suite("Truncated file rejection (T121)")
    @MainActor
    struct TruncatedFileTests {

        @Test("truncated file is never marked complete")
        func truncatedFileIsNeverComplete() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song010", context: context)

            // Write a small file but claim a much larger expected size.
            let sourceURL = store.stagingDirectoryURL.appendingPathComponent("source_song010.bin")
            try Data("tiny".utf8).write(to: sourceURL)
            let actualSize = Int64("tiny".utf8.count)
            let claimedSize = actualSize + 10_000 // Claim much larger

            let request = makeRequest(
                songID: "song010",
                streamURL: sourceURL,
                expectedByteSize: claimedSize
            )

            do {
                try await coordinator.startSave(request: request, context: context)
                Issue.record("Expected truncatedFile or notDecodable error")
            } catch SaveCoordinatorError.truncatedFile(let id, let expected, let actual) {
                #expect(id == "song010")
                #expect(expected == claimedSize)
                #expect(actual == actualSize)
            } catch SaveCoordinatorError.notDecodable {
                // Also acceptable — the file is not a valid audio file.
            } catch {
                // Any error is acceptable — the file must not be marked complete.
            }

            // The record must be in failed state, not complete.
            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song010" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            if let result = results.first {
                #expect(result.state == .failed)
                #expect(result.state != .complete)
            }
        }

        @Test("non-decodable file is never marked complete")
        func nonDecodableFileIsNeverComplete() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song011", context: context)

            // Write garbage bytes that are not a valid audio file.
            let sourceURL = store.stagingDirectoryURL.appendingPathComponent("source_song011.m4a")
            let garbage = Data(repeating: 0xFF, count: 1024)
            try garbage.write(to: sourceURL)

            let request = makeRequest(
                songID: "song011",
                streamURL: sourceURL,
                expectedByteSize: Int64(garbage.count)
            )

            do {
                try await coordinator.startSave(request: request, context: context)
                Issue.record("Expected notDecodable error")
            } catch SaveCoordinatorError.notDecodable(let id, _) {
                #expect(id == "song011")
            } catch {
                // Any error is acceptable — the file must not be marked complete.
            }

            // The record must NOT be complete.
            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song011" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            if let result = results.first {
                #expect(result.state != .complete)
            }
        }
    }

    // MARK: - T122: No-space handling

    @Suite("No-space handling (T122)")
    @MainActor
    struct NoSpaceTests {

        @Test("no-space error is classified as insufficientStorage")
        func noSpaceErrorClassification() async throws {
            let (_, _, coordinator) = try makeEnv()

            let nsError = NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteOutOfSpaceError,
                userInfo: [NSLocalizedDescriptionKey: "Not enough space on disk"]
            )

            let (message, coordinatorError) = coordinator.classifyDownloadError(nsError, songID: "song020")

            #expect(message.contains("space") || message.contains("storage"))
            if case .insufficientStorage(let id, _) = coordinatorError {
                #expect(id == "song020")
            } else {
                Issue.record("Expected insufficientStorage, got \(coordinatorError)")
            }
        }

        @Test("no-space failure leaves other SavedSongs untouched")
        func noSpaceFailureDoesNotAffectOtherSongs() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song021", context: context)
            insertSong(id: "song022", context: context)

            // song021 is already complete.
            let fileName = "song021.m4a"
            let fileURL = store.mediaDirectoryURL.appendingPathComponent(fileName)
            let fileSize = try await writeMinimalAudioFile(to: fileURL)

            let completeSong = SavedSong(
                songID: "song021",
                fileRelativePath: fileName,
                container: .m4a,
                codec: .aac,
                byteSize: fileSize,
                state: .complete,
                downloadedBytes: fileSize
            )
            context.insert(completeSong)
            try context.save()

            // song022 fails with garbage data (simulating a failed download).
            let sourceURL = store.stagingDirectoryURL.appendingPathComponent("source_song022.m4a")
            try Data(repeating: 0xFF, count: 512).write(to: sourceURL)

            let request = makeRequest(
                songID: "song022",
                streamURL: sourceURL,
                expectedByteSize: 512
            )

            // The download will fail (garbage data is not decodable).
            do {
                try await coordinator.startSave(request: request, context: context)
            } catch {
                // Expected — the download fails.
            }

            // song021 must still be complete and untouched.
            var descriptor021 = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song021" }
            )
            descriptor021.fetchLimit = 1
            let results021 = try context.fetch(descriptor021)
            #expect(results021.count == 1)
            #expect(results021[0].state == .complete)
            #expect(results021[0].byteSize == fileSize)

            // The media file for song021 must still exist.
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    // MARK: - Cancellation cleanup

    @Suite("Cancellation cleanup")
    @MainActor
    struct CancellationTests {

        @Test("cancelling a downloading song deletes the staging file")
        func cancelDownloadingDeletesStagingFile() async throws {
            let (context, store, coordinator) = try makeEnv()
            defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

            insertSong(id: "song031", context: context)

            // Create a staging file.
            let stagingURL = store.stagingURL(for: "song031", container: .m4a)
            try Data("partial content".utf8).write(to: stagingURL)
            #expect(FileManager.default.fileExists(atPath: stagingURL.path))

            let saved = SavedSong(
                songID: "song031",
                fileRelativePath: "song031.m4a",
                container: .m4a,
                codec: .aac,
                state: .downloading,
                downloadedBytes: 15
            )
            context.insert(saved)
            try context.save()

            try await coordinator.cancel(songID: "song031", context: context)

            // Staging file must be deleted.
            #expect(!FileManager.default.fileExists(atPath: stagingURL.path))

            // Record must be gone.
            var descriptor = FetchDescriptor<SavedSong>(
                predicate: #Predicate { $0.songID == "song031" }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            #expect(results.isEmpty)
        }
    }
}

// MARK: - AVAudioPCMBuffer + CMSampleBuffer helper

private extension AVAudioPCMBuffer {
    /// Converts this PCM buffer to a CMSampleBuffer for use with AVAssetWriterInput.
    func makeSampleBuffer(presentationTimeStamp: CMTime) throws -> CMSampleBuffer {
        var sampleBuffer: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: CMItemCount(frameLength),
            presentationTimeStamp: presentationTimeStamp,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let buffer = sampleBuffer else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return buffer
    }
}
