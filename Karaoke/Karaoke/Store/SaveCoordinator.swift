import Foundation
import SwiftData
import AVFoundation

// MARK: - SaveRequest

/// Everything needed to start a download.
struct SaveRequest: Sendable {
    let songID: String
    let streamURL: URL
    /// Expected byte size from the upstream rendition. Used for progress and
    /// completion verification (T121). Nil means we cannot verify size.
    let expectedByteSize: Int64?
    let container: SavedContainer
    let codec: SavedCodec
    let averageBitrateBps: Int?
    /// The relative path under the media directory where the file will live
    /// once the atomic move completes.
    let fileRelativePath: String
}

// MARK: - SaveCoordinatorError

enum SaveCoordinatorError: Error, Sendable {
    /// The song is already saved or being downloaded.
    case alreadyExists(String)
    /// No SavedSong record found for the given song ID.
    case notFound(String)
    /// The download completed but the written file is smaller than expected.
    /// A truncated file must never be marked complete (data-model.md SavedSong Rules).
    case truncatedFile(songID: String, expected: Int64, actual: Int64)
    /// The download completed but AVFoundation cannot decode the file.
    /// A non-decodable file must never be marked complete (T121).
    case notDecodable(songID: String, path: String)
    /// The device ran out of storage space (T122).
    case insufficientStorage(songID: String, detail: String)
    /// A network error occurred during download.
    case networkError(songID: String, underlying: String)
    /// The download was cancelled by the caller.
    case cancelled(String)
}

// MARK: - SaveCoordinator

/// Manages the full lifecycle of saving a song for offline playback.
///
/// State machine (data-model.md SavedSong state machine):
/// ```
///   (none) ──start save──> pending ──> downloading ──> complete
///                              │              │
///                              │         ├─ no space ──> failed
///                              │         ├─ network ───> failed
///                              │         └─ cancelled ─> (none)  [partial file deleted]
///                              └─ cancelled ──────────> (none)
///                                   retry
///                         failed ──────────> pending
///                                   delete
///                        complete ──────────> (none)
/// ```
///
/// Invariants enforced:
/// - `complete` is only reachable after byte-count verification AND decodability
///   check (T121, FR-030).
/// - A failed save never touches an existing complete file — writes go to staging
///   and are moved atomically on success (T119, FR-033).
/// - No-space failure leaves every other SavedSong untouched (T122).
/// - Cancellation deletes the partial staging file.
///
/// `@MainActor` because SwiftData `ModelContext` and `@Model` objects are
/// main-actor-bound. Async work (URLSession, AVFoundation) is awaited without
/// blocking the main thread.
@MainActor
@Observable
final class SaveCoordinator {

    // MARK: Dependencies

    private let mediaStore: MediaStore

    // MARK: Init

    init(mediaStore: MediaStore) {
        self.mediaStore = mediaStore
    }

    // MARK: - Start save (pending → downloading → complete/failed)

    /// Begins downloading a song for offline playback.
    ///
    /// Creates a `SavedSong` record in `pending`, transitions to `downloading`,
    /// writes to the staging location, verifies the result, then moves atomically
    /// into the media directory and marks `complete`.
    ///
    /// - Parameter request: The download parameters.
    /// - Parameter context: The ModelContext to update.
    /// - Throws: `SaveCoordinatorError` on failure.
    func startSave(request: SaveRequest, context: ModelContext) async throws {
        // Guard: no duplicate saves.
        if let existing = try fetchSavedSong(songID: request.songID, context: context) {
            switch existing.state {
            case .complete, .downloading, .pending, .failed:
                throw SaveCoordinatorError.alreadyExists(request.songID)
            }
        }

        // Create the record in pending state.
        let savedSong = SavedSong(
            songID: request.songID,
            fileRelativePath: request.fileRelativePath,
            container: request.container,
            codec: request.codec,
            averageBitrateBps: request.averageBitrateBps,
            byteSize: 0,
            savedAt: Date(),
            state: .pending,
            downloadedBytes: 0,
            lastError: nil
        )
        context.insert(savedSong)
        try context.save()

        try await performDownload(
            savedSong: savedSong,
            request: request,
            context: context
        )
    }

    // MARK: - Retry (failed → pending → downloading → complete/failed)

    /// Retries a failed download.
    ///
    /// Clears `lastError`, moves to `pending`, then starts the download.
    /// - Parameter songID: The song to retry.
    /// - Parameter request: Fresh download parameters (the stream URL may have changed).
    /// - Parameter context: The ModelContext to update.
    func retry(songID: String, request: SaveRequest, context: ModelContext) async throws {
        guard let savedSong = try fetchSavedSong(songID: songID, context: context) else {
            throw SaveCoordinatorError.notFound(songID)
        }
        guard savedSong.state == .failed else {
            throw SaveCoordinatorError.alreadyExists(songID)
        }

        // Retry moves back to pending; clear the previous error (data-model.md).
        savedSong.state = .pending
        savedSong.lastError = nil
        savedSong.downloadedBytes = 0
        try context.save()

        try await performDownload(
            savedSong: savedSong,
            request: request,
            context: context
        )
    }

    // MARK: - Cancel (downloading/pending → (none))

    /// Cancels an in-flight or pending download and deletes the partial file.
    ///
    /// Cancellation removes the SavedSong record entirely (data-model.md state
    /// machine: cancelled → (none)). The partial staging file is deleted.
    func cancel(songID: String, context: ModelContext) async throws {
        guard let savedSong = try fetchSavedSong(songID: songID, context: context) else {
            throw SaveCoordinatorError.notFound(songID)
        }

        // Delete the partial staging file.
        mediaStore.removeStagingFiles(for: songID)

        // Remove the record — cancelled → (none).
        context.delete(savedSong)
        try context.save()
    }

    // MARK: - Delete (complete → (none))

    /// Deletes a completed saved song: removes the file and the record together.
    ///
    /// data-model.md: "Deleting a SavedSong removes the file and the record
    /// together."
    func delete(songID: String, context: ModelContext) async throws {
        guard let savedSong = try fetchSavedSong(songID: songID, context: context) else {
            throw SaveCoordinatorError.notFound(songID)
        }

        // Delete the media file.
        let fileURL = mediaStore.mediaURL(for: savedSong.fileRelativePath)
        try? FileManager.default.removeItem(at: fileURL)

        // Also clean up any stale staging file.
        mediaStore.removeStagingFiles(for: songID)

        // Remove the record.
        context.delete(savedSong)
        try context.save()
    }

    // MARK: - Private: core download logic

    private func performDownload(
        savedSong: SavedSong,
        request: SaveRequest,
        context: ModelContext
    ) async throws {
        let songID = request.songID
        let stagingURL = mediaStore.stagingURL(for: songID, container: request.container)

        // Transition to downloading.
        savedSong.state = .downloading
        savedSong.downloadedBytes = 0
        try context.save()

        do {
            // Download to staging location (T119).
            let writtenBytes = try await downloadToStaging(
                from: request.streamURL,
                to: stagingURL
            )

            // Update progress.
            savedSong.downloadedBytes = writtenBytes
            try context.save()

            // T121: Verify byte count before marking complete.
            if let expected = request.expectedByteSize, writtenBytes < expected {
                // Truncated file — must never be marked complete (FR-030).
                try? FileManager.default.removeItem(at: stagingURL)
                let errorMsg = "Download incomplete: received \(writtenBytes) of \(expected) bytes. Try again."
                savedSong.state = .failed
                savedSong.lastError = errorMsg
                savedSong.downloadedBytes = 0
                try context.save()
                throw SaveCoordinatorError.truncatedFile(
                    songID: songID,
                    expected: expected,
                    actual: writtenBytes
                )
            }

            // T121: Verify the file is decodable by AVFoundation.
            // Does NOT go through the playback layer (per task seam requirement).
            try await verifyDecodable(stagingURL: stagingURL, songID: songID)

            // Atomic move from staging to media directory (T119, FR-033).
            // A failed save never touches an existing complete file because
            // we only reach this line after all verifications pass.
            let finalURL = mediaStore.mediaURL(for: request.fileRelativePath)
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)

            // Mark complete with the actual measured byte size.
            let actualSize = try measuredFileSize(at: finalURL)
            savedSong.state = .complete
            savedSong.byteSize = actualSize
            savedSong.downloadedBytes = actualSize
            savedSong.savedAt = Date()
            savedSong.lastError = nil
            try context.save()

        } catch let error as SaveCoordinatorError {
            // Already handled above (truncated, not-decodable).
            // Clean up staging if still present.
            try? FileManager.default.removeItem(at: stagingURL)
            throw error

        } catch let urlError as URLError where urlError.code == .cancelled {
            // Cancellation: clean up staging.
            try? FileManager.default.removeItem(at: stagingURL)
            throw SaveCoordinatorError.cancelled(songID)

        } catch {
            // T122: Classify the error — no-space vs network.
            // No-space failure leaves every other SavedSong untouched because
            // we only modify `savedSong` here, not any other record.
            try? FileManager.default.removeItem(at: stagingURL)

            let (errorMsg, coordinatorError) = classifyDownloadError(error, songID: songID)
            savedSong.state = .failed
            savedSong.lastError = errorMsg
            savedSong.downloadedBytes = 0
            try context.save()
            throw coordinatorError
        }
    }

    // MARK: - Private: URLSession download

    /// Downloads `url` to `stagingURL` and returns the number of bytes written.
    ///
    /// Uses `URLSession.shared.download(from:)` which suspends without blocking
    /// the main thread. The file is moved from URLSession's temp location to
    /// `stagingURL` atomically.
    private func downloadToStaging(from url: URL, to stagingURL: URL) async throws -> Int64 {
        let (tempURL, response) = try await URLSession.shared.download(from: url)

        // Check HTTP status.
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        // Move from URLSession's temp location to our staging location.
        // Remove any existing staging file first (idempotent retry).
        try? FileManager.default.removeItem(at: stagingURL)
        try FileManager.default.moveItem(at: tempURL, to: stagingURL)

        return try measuredFileSize(at: stagingURL)
    }

    // MARK: - Private: Completion verification (T121)

    /// Verifies the file at `stagingURL` is decodable by AVFoundation.
    ///
    /// Uses `AVURLAsset` to load the asset's tracks. A file that AVFoundation
    /// cannot decode must never be marked complete — FR-030 promises offline
    /// playback works.
    ///
    /// Does NOT go through the playback layer (per task seam requirement).
    private func verifyDecodable(stagingURL: URL, songID: String) async throws {
        let asset = AVURLAsset(url: stagingURL)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else {
                throw SaveCoordinatorError.notDecodable(
                    songID: songID,
                    path: stagingURL.lastPathComponent
                )
            }
        } catch let error as SaveCoordinatorError {
            throw error
        } catch {
            throw SaveCoordinatorError.notDecodable(
                songID: songID,
                path: stagingURL.lastPathComponent
            )
        }
    }

    // MARK: - Error classification (T122)

    /// Classifies a download error into a singer-facing message and a typed error.
    ///
    /// No-space errors leave `state = failed` with an actionable message and
    /// leave every other SavedSong untouched (T122, FR-033).
    func classifyDownloadError(
        _ error: Error,
        songID: String
    ) -> (message: String, error: SaveCoordinatorError) {
        let nsError = error as NSError

        // NSFileWriteOutOfSpaceError = 640
        let isNoSpace = (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))

        if isNoSpace {
            let msg = "Not enough storage space. Free up space and try again."
            return (msg, .insufficientStorage(songID: songID, detail: msg))
        }

        let isOffline = nsError.domain == NSURLErrorDomain && (
            nsError.code == NSURLErrorNotConnectedToInternet
            || nsError.code == NSURLErrorNetworkConnectionLost
            || nsError.code == NSURLErrorTimedOut
        )

        if isOffline {
            let msg = "Network unavailable. Check your connection and try again."
            return (msg, .networkError(songID: songID, underlying: msg))
        }

        let msg = "Download failed. Try again. (\(nsError.localizedDescription))"
        return (msg, .networkError(songID: songID, underlying: msg))
    }

    // MARK: - Private: Helpers

    private func fetchSavedSong(songID: String, context: ModelContext) throws -> SavedSong? {
        var descriptor = FetchDescriptor<SavedSong>(
            predicate: #Predicate { $0.songID == songID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func measuredFileSize(at url: URL) throws -> Int64 {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(resourceValues.fileSize ?? 0)
    }
}
