import Testing
import Foundation
import SwiftData
@testable import Karaoke

// MARK: - StorageAccountingTests (T128)

/// Tests for storage accounting in MediaStore.
///
/// Verifies data-model invariant 6:
/// "The sum of SavedSong.byteSize over `complete` entries equals the measured
/// size of the media directory minus staging."
///
/// A divergence indicates an orphaned file and is repaired at launch.
///
/// All tests use an in-memory ModelContainer and a temporary directory.
@Suite("StorageAccounting")
@MainActor
struct StorageAccountingTests {

    // MARK: - Test environment

    private func makeEnv() throws -> (context: ModelContext, store: MediaStore) {
        let store = try MediaStore(inMemory: true)
        let context = ModelContext(store.container)
        return (context, store)
    }

    private func insertSong(id: String, context: ModelContext) {
        let song = Song(
            id: id,
            title: "Test Song",
            channelName: "Test Channel",
            durationSeconds: 180
        )
        context.insert(song)
    }

    private func writeFile(name: String, bytes: Int, in directory: URL) throws -> Int64 {
        let url = directory.appendingPathComponent(name)
        let data = Data(repeating: 0xAB, count: bytes)
        try data.write(to: url)
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(resourceValues.fileSize ?? bytes)
    }

    // MARK: - Invariant 6: completedBytes matches measured media directory

    @Test("completedBytes equals sum of byteSize over complete entries")
    func completedBytesMatchesSumOfByteSizes() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        insertSong(id: "acc001", context: context)
        insertSong(id: "acc002", context: context)

        let size1 = try writeFile(name: "acc001.m4a", bytes: 1024, in: store.mediaDirectoryURL)
        let size2 = try writeFile(name: "acc002.m4a", bytes: 2048, in: store.mediaDirectoryURL)

        let saved1 = SavedSong(
            songID: "acc001",
            fileRelativePath: "acc001.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size1,
            state: .complete,
            downloadedBytes: size1
        )
        let saved2 = SavedSong(
            songID: "acc002",
            fileRelativePath: "acc002.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size2,
            state: .complete,
            downloadedBytes: size2
        )
        context.insert(saved1)
        context.insert(saved2)

        let report = try store.storageReport(context: context)
        #expect(report.completedBytes == size1 + size2)
    }

    @Test("completedBytes excludes failed and pending entries")
    func completedBytesExcludesNonCompleteEntries() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        insertSong(id: "acc010", context: context)
        insertSong(id: "acc011", context: context)
        insertSong(id: "acc012", context: context)

        let size1 = try writeFile(name: "acc010.m4a", bytes: 512, in: store.mediaDirectoryURL)

        let complete = SavedSong(
            songID: "acc010",
            fileRelativePath: "acc010.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size1,
            state: .complete,
            downloadedBytes: size1
        )
        let failed = SavedSong(
            songID: "acc011",
            fileRelativePath: "acc011.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: 0,
            state: .failed,
            downloadedBytes: 0
        )
        let pending = SavedSong(
            songID: "acc012",
            fileRelativePath: "acc012.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: 0,
            state: .pending,
            downloadedBytes: 0
        )
        context.insert(complete)
        context.insert(failed)
        context.insert(pending)

        let report = try store.storageReport(context: context)
        #expect(report.completedBytes == size1)
    }

    @Test("stagingBytes equals sum of downloadedBytes over downloading entries")
    func stagingBytesMatchesDownloadingEntries() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        insertSong(id: "acc020", context: context)
        insertSong(id: "acc021", context: context)

        let downloading1 = SavedSong(
            songID: "acc020",
            fileRelativePath: "acc020.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: 0,
            state: .downloading,
            downloadedBytes: 300
        )
        let downloading2 = SavedSong(
            songID: "acc021",
            fileRelativePath: "acc021.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: 0,
            state: .downloading,
            downloadedBytes: 700
        )
        context.insert(downloading1)
        context.insert(downloading2)

        let report = try store.storageReport(context: context)
        #expect(report.stagingBytes == 1000)
    }

    @Test("stagingBytes is reported separately from completedBytes")
    func stagingBytesAreSeparateFromCompleted() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        insertSong(id: "acc030", context: context)
        insertSong(id: "acc031", context: context)

        let size1 = try writeFile(name: "acc030.m4a", bytes: 1000, in: store.mediaDirectoryURL)

        let complete = SavedSong(
            songID: "acc030",
            fileRelativePath: "acc030.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size1,
            state: .complete,
            downloadedBytes: size1
        )
        let downloading = SavedSong(
            songID: "acc031",
            fileRelativePath: "acc031.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: 0,
            state: .downloading,
            downloadedBytes: 400
        )
        context.insert(complete)
        context.insert(downloading)

        let report = try store.storageReport(context: context)
        #expect(report.completedBytes == size1)
        #expect(report.stagingBytes == 400)
        #expect(report.totalBytes == size1 + 400)
    }

    @Test("empty store reports zero bytes")
    func emptyStoreReportsZero() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        let report = try store.storageReport(context: context)
        #expect(report.completedBytes == 0)
        #expect(report.stagingBytes == 0)
        #expect(report.totalBytes == 0)
    }

    // MARK: - Invariant 6: measured media directory matches completedBytes

    @Test("measured media directory bytes match completedBytes (invariant 6)")
    func measuredMediaBytesMatchCompletedBytes() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        insertSong(id: "acc040", context: context)
        insertSong(id: "acc041", context: context)

        let size1 = try writeFile(name: "acc040.m4a", bytes: 2000, in: store.mediaDirectoryURL)
        let size2 = try writeFile(name: "acc041.m4a", bytes: 3000, in: store.mediaDirectoryURL)

        let saved1 = SavedSong(
            songID: "acc040",
            fileRelativePath: "acc040.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size1,
            state: .complete,
            downloadedBytes: size1
        )
        let saved2 = SavedSong(
            songID: "acc041",
            fileRelativePath: "acc041.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size2,
            state: .complete,
            downloadedBytes: size2
        )
        context.insert(saved1)
        context.insert(saved2)

        let report = try store.storageReport(context: context)
        let measuredBytes = try store.measuredMediaBytes()

        // Invariant 6: completedBytes == measured media directory minus staging.
        // The staging directory is excluded from measuredMediaBytes().
        #expect(report.completedBytes == measuredBytes)
    }

    @Test("staging files do not count toward completedBytes (invariant 6)")
    func stagingFilesExcludedFromCompletedBytes() throws {
        let (context, store) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: store.mediaDirectoryURL) }

        insertSong(id: "acc050", context: context)

        // Write a complete file.
        let size1 = try writeFile(name: "acc050.m4a", bytes: 1500, in: store.mediaDirectoryURL)

        // Write a staging file (in the staging subdirectory).
        let stagingURL = store.stagingURL(for: "acc050_staging", container: .m4a)
        try Data(repeating: 0xCC, count: 500).write(to: stagingURL)

        let saved = SavedSong(
            songID: "acc050",
            fileRelativePath: "acc050.m4a",
            container: .m4a,
            codec: .aac,
            byteSize: size1,
            state: .complete,
            downloadedBytes: size1
        )
        context.insert(saved)

        let report = try store.storageReport(context: context)
        let measuredBytes = try store.measuredMediaBytes()

        // completedBytes should equal the measured media directory (staging excluded).
        #expect(report.completedBytes == measuredBytes)
        // The staging file (500 bytes) must not appear in completedBytes.
        #expect(report.completedBytes == size1)
    }

    // MARK: - StorageReport computed property

    @Test("totalBytes is completedBytes + stagingBytes")
    func totalBytesIsSum() throws {
        let report = StorageReport(completedBytes: 1000, stagingBytes: 250)
        #expect(report.totalBytes == 1250)
    }

    @Test("StorageReport with zero staging has totalBytes equal to completedBytes")
    func totalBytesWithZeroStaging() throws {
        let report = StorageReport(completedBytes: 5000, stagingBytes: 0)
        #expect(report.totalBytes == 5000)
    }
}
