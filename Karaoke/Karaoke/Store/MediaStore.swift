import Foundation
import SwiftData

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

    // MARK: Init

    init() throws {
        let schema = Schema([
            Song.self,
            SavedSong.self,
            Favourite.self,
            QueueEntry.self,
            PerformanceSettings.self,
            LyricsTrack.self,
            LyricsLine.self,
            LyricsWord.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        self.container = try ModelContainer(for: schema, configurations: modelConfiguration)
        self.mediaDirectoryURL = try Self.resolveMediaDirectory()
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
            LyricsTrack.self,
            LyricsLine.self,
            LyricsWord.self,
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
        } else {
            self.mediaDirectoryURL = try Self.resolveMediaDirectory()
        }
    }

    // MARK: Path helpers

    /// Resolves a `SavedSong.fileRelativePath` to an absolute URL.
    ///
    /// - Parameter relativePath: The value stored in `SavedSong.fileRelativePath`.
    /// - Returns: An absolute URL within `mediaDirectoryURL`.
    func mediaURL(for relativePath: String) -> URL {
        mediaDirectoryURL.appendingPathComponent(relativePath)
    }

    // MARK: Private helpers

    /// Returns (and creates if needed) the app's media directory.
    ///
    /// Stored in Application Support so it is backed up and survives reinstalls
    /// as long as the bundle ID is unchanged. The directory name is fixed so
    /// relative paths remain valid across launches.
    private static func resolveMediaDirectory() throws -> URL {
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
        return mediaDir
    }
}
