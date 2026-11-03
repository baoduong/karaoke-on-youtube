import Foundation
import SwiftData

// MARK: - StorageReport

/// Snapshot of storage used by saved songs (FR-031, data-model invariant 6).
///
/// Staging bytes are reported separately so the singer understands that
/// cancelling an in-flight download reclaims them.
struct StorageReport: Sendable {
    /// Sum of `byteSize` over all `complete` SavedSong entries.
    let completedBytes: Int64
    /// Sum of `downloadedBytes` over all `downloading` SavedSong entries.
    /// Reported separately — a cancel reclaims these (FR-031).
    let stagingBytes: Int64

    var totalBytes: Int64 { completedBytes + stagingBytes }
}

// MARK: - MediaStore

/// Owns the SwiftData `ModelContainer` and the media directory path for saved
/// audio files (T024).
///
/// Audio bytes stay out of the database — only relative file paths are stored
/// (data-model.md SavedSong Rules). This type exposes the media directory URL
/// so the rest of the app can resolve relative paths to absolute ones without
/// knowing the sandbox layout.
///
/// The container is configured with all persisted entity types. Transient types
/// (AudioRendition, StreamAddress, PlaybackSession, Suggestion) are not included
/// — they are never persisted (data-model.md persistence boundary).
@MainActor
final class MediaStore {

    // MARK: Shared instance

    /// The application-wide store. Initialised once at launch in `KaraokeApp`.
    static let shared: MediaStore = {
        do {
            return try MediaStore()
        } catch {
            // A store that cannot be created is a fatal configuration error.
            // This is the one place a fatalError is acceptable: without a
            // working store the app cannot function at all, and the error
            // message names the cause.
            fatalError("MediaStore: failed to create ModelContainer — \(error)")
        }
    }()

    // MARK: Public interface

    /// The SwiftData container holding all persisted entities.
    let container: ModelContainer

    /// The directory where saved audio files are written.
    ///
    /// Paths stored in `SavedSong.fileRelativePath` are relative to this URL.
    /// Resolve them with `mediaURL(for:)`.
    ///
    /// The directory is created on first access if it does not exist.
    let mediaDirectoryURL: URL

    /// The staging directory where in-flight downloads are written before
    /// atomic move into `mediaDirectoryURL` (T119, FR-033).
    ///
    /// A failed save never touches the media directory because it only ever
    /// writes here. On completion the file is moved atomically.
    let stagingDirectoryURL: URL

    // MARK: Init

    init() throws {
        let schema = Schema([
            Song.self,
            SavedSong.self,
            Favourite.self,
            QueueEntry.self,
            PerformanceSettings.self,
            SessionLog.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        self.container = try ModelContainer(for: schema, configurations: modelConfiguration)
        let (media, staging) = try Self.resolveDirectories()
        self.mediaDirectoryURL = media
        self.stagingDirectoryURL = staging
    }

    /// Creates an in-memory container for use in tests.
    ///
    /// The media directory is a temporary directory that callers are responsible
    /// for cleaning up.
    init(inMemory: Bool) throws {
        let schema = Schema([
            Song.self,
            SavedSong.self,
            Favourite.self,
            QueueEntry.self,
            PerformanceSettings.self,
            SessionLog.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        self.container = try ModelContainer(for: schema, configurations: modelConfiguration)

        if inMemory {
            // Use a temp directory for tests so they never touch the real media dir.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("KaraokeTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            self.mediaDirectoryURL = tmp
            let staging = tmp.appendingPathComponent("staging", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            self.stagingDirectoryURL = staging
        } else {
            let (media, staging) = try Self.resolveDirectories()
            self.mediaDirectoryURL = media
            self.stagingDirectoryURL = staging
        }
    }

    // MARK: Path helpers

    /// Resolves a `SavedSong.fileRelativePath` to an absolute URL in the media directory.
    ///
    /// - Parameter relativePath: The value stored in `SavedSong.fileRelativePath`.
    /// - Returns: An absolute URL within `mediaDirectoryURL`.
    func mediaURL(for relativePath: String) -> URL {
        mediaDirectoryURL.appendingPathComponent(relativePath)
    }

    /// Returns the staging URL for a download in progress (T119).
    ///
    /// The staging file is written here and moved atomically to `mediaURL(for:)`
    /// on successful completion. A failed save never touches the media directory.
    ///
    /// The file keeps its real container extension rather than a generic one.
    /// AVFoundation infers a container from the path extension, so verifying
    /// decodability (T121) against a `.staging` suffix rejects perfectly valid
    /// audio. Being inside the staging directory is what marks it as staging.
    func stagingURL(for songID: String, container: SavedContainer) -> URL {
        stagingDirectoryURL.appendingPathComponent("\(songID).\(container.pathExtension)")
    }

    /// Removes every staging artefact for a song, whatever container it used.
    ///
    /// Cancel and delete paths know the song but not necessarily the container
    /// it was being saved in, and a retry in a different container must not
    /// strand the earlier partial file.
    func removeStagingFiles(for songID: String) {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for url in contents ?? [] where url.lastPathComponent.hasPrefix("\(songID).") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Storage accounting (T123)

    /// Computes the current storage report from the live model context.
    ///
    /// - Parameter context: The ModelContext to query. Must be on the main actor.
    /// - Returns: A `StorageReport` with completed and staging bytes.
    ///
    /// Total = sum of `byteSize` over `complete` entries.
    /// Staging = sum of `downloadedBytes` over `downloading` entries.
    /// These are reported separately so the singer understands a cancel reclaims
    /// staging bytes (FR-031, data-model invariant 6).
    func storageReport(context: ModelContext) throws -> StorageReport {
        let allSaved = try context.fetch(FetchDescriptor<SavedSong>())

        var completedBytes: Int64 = 0
        var stagingBytes: Int64 = 0

        for saved in allSaved {
            switch saved.state {
            case .complete:
                completedBytes += saved.byteSize
            case .downloading:
                stagingBytes += saved.downloadedBytes
            case .pending, .failed:
                break
            }
        }

        return StorageReport(completedBytes: completedBytes, stagingBytes: stagingBytes)
    }

    /// Measures the actual bytes in the media directory, excluding the staging
    /// subdirectory. Used to verify data-model invariant 6.
    func measuredMediaBytes() throws -> Int64 {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mediaDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        )

        var total: Int64 = 0
        for url in contents {
            // Skip the staging subdirectory.
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { continue }

            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(resourceValues.fileSize ?? 0)
        }
        return total
    }

    // MARK: Private helpers

    /// Returns (and creates if needed) the app's media and staging directories.
    ///
    /// Stored in Application Support so it is backed up and survives reinstalls
    /// as long as the bundle ID is unchanged. The directory name is fixed so
    /// relative paths remain valid across launches.
    private static func resolveDirectories() throws -> (media: URL, staging: URL) {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let mediaDir = appSupport.appendingPathComponent("KaraokeMedia", isDirectory: true)
        if !FileManager.default.fileExists(atPath: mediaDir.path) {
            try FileManager.default.createDirectory(
                at: mediaDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let stagingDir = mediaDir.appendingPathComponent("staging", isDirectory: true)
        if !FileManager.default.fileExists(atPath: stagingDir.path) {
            try FileManager.default.createDirectory(
                at: stagingDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return (mediaDir, stagingDir)
    }
}
