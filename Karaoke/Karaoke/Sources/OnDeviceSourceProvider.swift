import Foundation
@preconcurrency import YouTubeKit

// MARK: - OnDeviceSourceProvider

/// Resolves YouTube videos on-device using YouTubeKit.
///
/// This is the module Constitution Principle II is written about: it wraps an
/// undocumented upstream that changes without notice, and it is expected to
/// break on roughly the cadence the reference extractor does (research.md R2
/// measured 12 commits in 90 days). Keep every YouTubeKit detail inside this
/// file so a break is a one-file fix.
///
/// YouTubeKit 0.4.10 public API used — verified against the checked-out source,
/// not assumed:
///   `YouTube(videoID:)`, `checkAvailability()`, `streams`, `metadata`,
///   `Stream.url`, `.fileExtension`, `.audioCodec`, `.averageBitrate`,
///   `.bitrate`, `.includesAudioTrack`, `.includesVideoTrack`,
///   `.isNativelyPlayable`, `Collection<Stream>.stream(withITag:)`,
///   `YouTubeKitError`.
///
/// **Deliberately not used: `Stream.itag.itag`.** `ITag` is a public struct but
/// its integer `itag` property is `internal` to YouTubeKit, so it cannot be read
/// from this module. The itag is instead parsed from the stream URL's `itag`
/// query parameter, which is what YouTube actually serves on the wire. Lookup in
/// the other direction uses `stream(withITag:)`, which is public and works
/// because its closure body executes inside YouTubeKit.
final class OnDeviceSourceProvider: SourceProvider, @unchecked Sendable {

    let identifier = SourceProviderID(rawValue: "on-device")

    private let networkTimeout: TimeInterval = 30

    /// Maximum number of audio-only streams to process from a single video.
    ///
    /// A multi-hour compilation can have hundreds of format entries. Processing
    /// all of them would load the full format list into memory and iterate it
    /// completely. Capping at 50 covers every real rendition set (YouTube
    /// typically offers 4–8 audio-only formats) while bounding memory use for
    /// pathological inputs (spec edge case: Very long source, T137).
    private let maxAudioStreams = 50

    func healthCheck() async -> ProviderHealth {
        .healthy
    }

    // MARK: - Capabilities this provider does not have

    /// YouTubeKit resolves a known video; it does not search.
    ///
    /// This throws rather than returning an empty array on purpose. An empty
    /// array means "the upstream was asked and found nothing", which is a
    /// content-side answer the singer should act on. "We cannot search at all"
    /// is a mechanism-side fact the router must act on by falling through to a
    /// provider that can. Conflating the two is precisely the misclassification
    /// contracts/source-provider.md warns about (FR-008).
    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata] {
        throw .resolutionFailed(
            query,
            stage: .fetchingPage,
            detail: "on-device provider cannot search; route search to the Data API provider"
        )
    }

    /// YouTubeKit's `YouTubeMetadata` exposes only `title`, `description` and
    /// `thumbnail` — there is no channel name and no duration.
    ///
    /// `SongMetadata` requires both, and `Song` validation rejects a
    /// `durationSeconds` that is not greater than zero (data-model.md). Returning
    /// a placeholder duration of 0 would therefore produce a value that is
    /// silently discarded at persistence time, which looks like "the song
    /// vanished" rather than "we could not read its metadata".
    ///
    /// So this reports a mechanism-side failure and lets the router fall through
    /// to the Data API provider, which supplies both fields.
    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata {
        throw .resolutionFailed(
            reference.songID,
            stage: .parsingPlayerResponse,
            detail: "YouTubeKit exposes no channel name or duration; route metadata to the Data API provider"
        )
    }

    // MARK: - Renditions

    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition] {
        let streams = try await loadStreams(songID: songID, stage: .parsingFormats)

        guard !Task.isCancelled else { throw SourceError.cancelled }

        // Audio-only renditions. A muxed stream carries lower-quality audio than
        // the best audio-only rendition and drags video bytes playback never uses.
        // Cap at maxAudioStreams to bound memory for very long compilations (T137).
        let audioStreams = streams
            .filter { $0.includesAudioTrack && !$0.includesVideoTrack }
            .prefix(maxAudioStreams)

        var renditions: [AudioRendition] = []
        var seenItags = Set<Int>()

        for stream in audioStreams {
            guard let itag = Self.itag(fromStreamURL: stream.url) else {
                // The wire format no longer carries an itag we can read. That is
                // an upstream shape change, not an unavailable song.
                throw SourceError.upstreamContractChanged(
                    detail: "stream URL carries no readable itag query parameter"
                )
            }

            // A duplicate itag within one song means the parse is wrong. Failing
            // beats silently picking one of two things claiming the same identity.
            guard seenItags.insert(itag).inserted else {
                throw SourceError.resolutionFailed(
                    songID,
                    stage: .parsingFormats,
                    detail: "duplicate itag \(itag) in one rendition set"
                )
            }

            renditions.append(
                AudioRendition(
                    itag: itag,
                    container: Self.mapContainer(stream.fileExtension),
                    codec: Self.mapCodec(stream.audioCodec),
                    averageBitrateBps: stream.averageBitrate ?? stream.bitrate,
                    sampleRateHz: nil,
                    channelCount: nil,
                    approximateByteSize: nil,
                    // Ask the platform rather than consulting a hardcoded codec
                    // list, so the answer stays correct across OS versions.
                    isDecodableOnDevice: stream.isNativelyPlayable
                )
            )
        }

        // The full set is returned deliberately. Ranking happens in the pure
        // function in RenditionSelection so SC-004 is verifiable offline; a
        // provider must never pre-filter to "the best one".
        return renditions
    }

    func streamAddress(for songID: SongID, itag: Int) async throws(SourceError) -> StreamAddress {
        let streams = try await loadStreams(songID: songID, stage: .buildingAddress)

        guard !Task.isCancelled else { throw SourceError.cancelled }

        guard let stream = streams.stream(withITag: itag) else {
            throw SourceError.unknownItag(songID, itag: itag)
        }

        let url = stream.url
        return StreamAddress(
            url: url,
            renditionItag: itag,
            expiresAt: StreamAddress.parseExpiry(from: url),
            resolvedAt: Date(),
            supportsRangeRequests: StreamAddress.parseSupportsRangeRequests(from: url)
        )
    }

    // MARK: - Shared loading

    /// Availability check then stream fetch, with the stage attributed correctly
    /// so a maintainer can tell which half failed without a debugger.
    private func loadStreams(
        songID: SongID,
        stage: ResolutionStage
    ) async throws(SourceError) -> [YouTubeKit.Stream] {
        guard !Task.isCancelled else { throw SourceError.cancelled }

        do {
            try await withTimeout(networkTimeout, stage: .fetchingPage) {
                try await YouTube(videoID: songID).checkAvailability()
            }
        } catch let error as SourceError {
            throw error
        } catch {
            throw Self.classify(error, songID: songID, stage: .fetchingPage)
        }

        do {
            return try await withTimeout(networkTimeout, stage: stage) {
                try await YouTube(videoID: songID).streams
            }
        } catch let error as SourceError {
            throw error
        } catch {
            throw Self.classify(error, songID: songID, stage: stage)
        }
    }

    // MARK: - itag from the wire

    /// Reads the `itag` query parameter from a YouTube stream URL.
    ///
    /// Exists because `ITag.itag` is internal to YouTubeKit. The query parameter
    /// is what YouTube itself puts on the URL, so this reads the same number the
    /// library does, through public API only — and without patching the package,
    /// which would live in DerivedData and vanish on the next clean build.
    static func itag(fromStreamURL url: URL) -> Int? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "itag" })?.value,
              let value = Int(raw)
        else {
            return nil
        }
        return value
    }

    // MARK: - Error classification

    /// Maps an upstream failure onto the taxonomy, keeping the content-side and
    /// mechanism-side groups strictly apart. A parse failure must never be
    /// reported as "song unavailable" — that hides breakage until the whole
    /// library looks empty (contracts/source-provider.md).
    static func classify(_ error: Error, songID: SongID, stage: ResolutionStage) -> SourceError {
        if let error = error as? YouTubeKitError {
            return classifyUpstream(error, songID: songID, stage: stage)
        }
        if let error = error as? URLError {
            return classifyTransport(error, songID: songID, stage: stage)
        }
        if error is CancellationError {
            return .cancelled
        }
        return .resolutionFailed(songID, stage: stage, detail: "unexpected \(type(of: error))")
    }

    private static func classifyUpstream(
        _ error: YouTubeKitError,
        songID: SongID,
        stage: ResolutionStage
    ) -> SourceError {
        switch error {
        // Content-side: the upstream explicitly said this item is unavailable.
        case .videoUnavailable:     return .notFound(songID)
        case .videoPrivate:         return .private_(songID)
        case .videoAgeRestricted:   return .ageRestricted(songID)
        case .videoRegionBlocked:   return .regionBlocked(songID, region: nil)
        case .liveStreamError:      return .liveStreamUnsupported(songID)
        case .membersOnly:          return .private_(songID)
        case .recordingUnavailable: return .removed(songID)

        // Mechanism-side: the upstream said nothing; our parsing failed.
        case .extractError:
            return .resolutionFailed(songID, stage: stage, detail: "extractError")
        case .htmlParseError:
            return .resolutionFailed(songID, stage: .parsingPlayerResponse, detail: "htmlParseError")
        case .regexMatchError:
            return .cipherFailure(detail: "regexMatchError at \(stage)")
        case .maxRetriesExceeded:
            return .resolutionFailed(songID, stage: stage, detail: "maxRetriesExceeded")
        }
    }

    private static func classifyTransport(
        _ error: URLError,
        songID: SongID,
        stage: ResolutionStage
    ) -> SourceError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timeout(stage: stage)
        case .cancelled:
            return .cancelled
        default:
            return .resolutionFailed(songID, stage: stage, detail: "URLError \(error.code.rawValue)")
        }
    }

    // MARK: - Mapping

    static func mapContainer(_ fileExtension: FileExtension) -> Container {
        switch fileExtension {
        case .m4a:  return .m4a
        case .webm: return .webm
        case .mp4:  return .mp4
        default:    return .other(fileExtension.rawValue)
        }
    }

    static func mapCodec(_ audioCodec: AudioCodec?) -> Codec {
        guard let audioCodec else { return .other("unknown") }
        switch audioCodec {
        case .mp4a:             return .aac
        case .opus:             return .opus
        case .unknown(let raw): return .other(raw)
        default:                return .other(String(describing: audioCodec))
        }
    }

    // MARK: - Timeout

    /// Races the operation against a deadline so a hung resolution surfaces as
    /// `timeout(stage:)`, which names where it hung.
    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        stage: ResolutionStage,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SourceError.timeout(stage: stage)
            }
            guard let result = try await group.next() else {
                throw SourceError.resolutionFailed(
                    "unknown",
                    stage: stage,
                    detail: "timeout group produced no result"
                )
            }
            group.cancelAll()
            return result
        }
    }
}
