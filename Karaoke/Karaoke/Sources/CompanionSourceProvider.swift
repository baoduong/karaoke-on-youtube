// T134 — CompanionSourceProvider.
//
// Calls the companion HTTP service (Tools/companion-service/) to resolve
// renditions and stream addresses server-side. Registered in the router chain
// after OnDeviceSourceProvider so it acts as the fallback when on-device
// resolution breaks.
//
// This is the most important task in the phase: on-device resolution breaking
// is a scheduled event (the reference extractor took 12 commits in 90 days),
// and a server-side fix avoids the rebuild-and-re-sign the singer must perform
// by hand (contracts/source-provider.md, FR-036).
//
// The companion service address is read from UserDefaults so the singer can
// configure it in Settings without a rebuild (T135).
//
// Satisfies: FR-003, FR-004, FR-007, FR-008, FR-036

import Foundation

// MARK: - CompanionSourceProvider

/// Resolves YouTube audio via the companion HTTP service.
///
/// The companion service wraps yt-dlp on the singer's own machine. When
/// on-device resolution breaks, updating yt-dlp and restarting the service
/// fixes it without touching the iOS app.
///
/// Health check: the provider is unhealthy when no address is configured or
/// when the service does not respond to /health. The router skips unhealthy
/// providers, so a misconfigured companion is invisible to the singer.
final class CompanionSourceProvider: SourceProvider, @unchecked Sendable {

    let identifier = SourceProviderID(rawValue: "companion")

    // MARK: Configuration

    static let addressKey = "companionServiceAddress"
    private let networkTimeout: TimeInterval = 30

    private var baseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: Self.addressKey),
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    // MARK: SourceProvider — health

    func healthCheck() async -> ProviderHealth {
        guard let base = baseURL else {
            return .unhealthy(reason: "no companion address configured")
        }
        let healthURL = base.appendingPathComponent("health")
        do {
            let (_, response) = try await withTimeout(5, stage: .fetchingPage) {
                try await URLSession.shared.data(from: healthURL)
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .unhealthy(reason: "companion /health returned non-200")
            }
            return .healthy
        } catch {
            return .unhealthy(reason: "companion /health unreachable: \(error.localizedDescription)")
        }
    }

    // MARK: SourceProvider — search

    /// Searches through the companion service, which has no key and no quota.
    ///
    /// This is the primary search path. The Data API allows 100 searches per
    /// day, which one party exhausts, so it is the fallback rather than the
    /// default. The companion drives YouTube's own search, so results match
    /// what a browser shows — which matters for Vietnamese karaoke channels
    /// that the Data API ranks poorly.
    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata] {
        guard !Task.isCancelled else { throw SourceError.cancelled }
        let base = try requireBaseURL(songID: query)

        guard var components = URLComponents(
            url: base.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SourceError.resolutionFailed(query, stage: .fetchingPage, detail: "could not build companion URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            throw SourceError.resolutionFailed(query, stage: .fetchingPage, detail: "could not build companion URL")
        }

        let data = try await fetch(url: url, songID: query, stage: .fetchingPage)
        guard !Task.isCancelled else { throw SourceError.cancelled }
        return try Self.parseSearchResults(data: data, query: query)
    }

    // MARK: SourceProvider — metadata

    /// Full metadata including channel and duration, neither of which the
    /// on-device resolver can read.
    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata {
        guard !Task.isCancelled else { throw SourceError.cancelled }
        let songID = reference.songID
        let base = try requireBaseURL(songID: songID)

        guard var components = URLComponents(
            url: base.appendingPathComponent("metadata"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SourceError.resolutionFailed(songID, stage: .parsingPlayerResponse, detail: "could not build companion URL")
        }
        components.queryItems = [URLQueryItem(name: "id", value: songID)]
        guard let url = components.url else {
            throw SourceError.resolutionFailed(songID, stage: .parsingPlayerResponse, detail: "could not build companion URL")
        }

        let data = try await fetch(url: url, songID: songID, stage: .parsingPlayerResponse)
        guard !Task.isCancelled else { throw SourceError.cancelled }

        guard let object = try? JSONSerialization.jsonObject(data) as? [String: Any],
              let parsed = Self.parseSongMetadata(object)
        else {
            throw SourceError.upstreamContractChanged(detail: "companion /metadata returned an unusable shape")
        }
        return parsed
    }

    // MARK: Search parsing

    static func parseSearchResults(data: Data, query: String) throws(SourceError) -> [SongMetadata] {
        guard let root = try? JSONSerialization.jsonObject(data) as? [String: Any],
              let rawResults = root["results"] as? [[String: Any]]
        else {
            throw SourceError.upstreamContractChanged(detail: "companion /search returned an unusable shape")
        }
        // Entries missing a usable duration are dropped rather than surfaced:
        // Song validation rejects a non-positive duration, so passing one
        // through makes the result vanish later with no visible reason.
        return rawResults.compactMap(parseSongMetadata)
    }

    static func parseSongMetadata(_ raw: [String: Any]) -> SongMetadata? {
        guard let id = raw["id"] as? String, !id.isEmpty,
              let title = raw["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty,
              let duration = raw["durationSeconds"] as? Int, duration > 0
        else {
            return nil
        }
        let channel = (raw["channelName"] as? String) ?? ""
        return SongMetadata(
            id: id,
            title: title,
            channelName: channel.isEmpty ? "Unknown" : channel,
            durationSeconds: duration,
            thumbnailURL: (raw["thumbnailURL"] as? String).flatMap(URL.init(string:))
        )
    }

    // MARK: SourceProvider — renditions

    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition] {
        guard !Task.isCancelled else { throw SourceError.cancelled }
        let base = try requireBaseURL(songID: songID)

        var components = URLComponents(url: base.appendingPathComponent("resolve-renditions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: songID)]
        guard let url = components.url else {
            throw SourceError.resolutionFailed(songID, stage: .buildingAddress, detail: "could not build companion URL")
        }

        let data = try await fetch(url: url, songID: songID, stage: .parsingFormats)

        guard !Task.isCancelled else { throw SourceError.cancelled }

        return try parseRenditions(data: data, songID: songID)
    }

    // MARK: SourceProvider — stream address

    func streamAddress(for songID: SongID, itag: Int) async throws(SourceError) -> StreamAddress {
        guard !Task.isCancelled else { throw SourceError.cancelled }
        let base = try requireBaseURL(songID: songID)

        var components = URLComponents(url: base.appendingPathComponent("resolve-address"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: songID),
            URLQueryItem(name: "itag", value: String(itag)),
        ]
        guard let url = components.url else {
            throw SourceError.resolutionFailed(songID, stage: .buildingAddress, detail: "could not build companion URL")
        }

        let data = try await fetch(url: url, songID: songID, stage: .buildingAddress)

        guard !Task.isCancelled else { throw SourceError.cancelled }

        return try parseAddress(data: data, songID: songID, itag: itag)
    }

    // MARK: Internal — parsing (also used by tests via @testable import)

    func parseRenditionsInternal(data: Data, songID: SongID) throws(SourceError) -> [AudioRendition] {
        try parseRenditions(data: data, songID: songID)
    }

    func parseAddressInternal(data: Data, songID: SongID, itag: Int) throws(SourceError) -> StreamAddress {
        try parseAddress(data: data, songID: songID, itag: itag)
    }

    // MARK: Private — parsing

    private func parseRenditions(data: Data, songID: SongID) throws(SourceError) -> [AudioRendition] {
        guard let json = try? JSONSerialization.jsonObject(data) as? [String: Any],
              let renditionsArray = json["renditions"] as? [[String: Any]] else {
            throw SourceError.upstreamContractChanged(detail: "companion /resolve-renditions response is not {renditions:[...]}")
        }

        var renditions: [AudioRendition] = []
        var seenItags = Set<Int>()

        for item in renditionsArray {
            guard let itag = item["itag"] as? Int else { continue }

            guard seenItags.insert(itag).inserted else {
                throw SourceError.resolutionFailed(
                    songID,
                    stage: .parsingFormats,
                    detail: "companion returned duplicate itag \(itag)"
                )
            }

            let container = mapContainer(item["container"] as? String ?? "")
            let codec = mapCodec(item["codec"] as? String ?? "")
            let bitrate = item["averageBitrateBps"] as? Int

            renditions.append(AudioRendition(
                itag: itag,
                container: container,
                codec: codec,
                averageBitrateBps: bitrate,
                sampleRateHz: nil,
                channelCount: nil,
                approximateByteSize: nil,
                isDecodableOnDevice: item["isDecodableOnDevice"] as? Bool ?? true
            ))
        }

        return renditions
    }

    private func parseAddress(data: Data, songID: SongID, itag: Int) throws(SourceError) -> StreamAddress {
        guard let json = try? JSONSerialization.jsonObject(data) as? [String: Any] else {
            throw SourceError.upstreamContractChanged(detail: "companion /resolve-address response is not a JSON object")
        }

        if let errorMsg = json["error"] as? String {
            if errorMsg.contains("not found") {
                throw SourceError.unknownItag(songID, itag: itag)
            }
            throw SourceError.resolutionFailed(songID, stage: .buildingAddress, detail: "companion error: \(errorMsg)")
        }

        guard let urlString = json["url"] as? String,
              let url = URL(string: urlString) else {
            throw SourceError.upstreamContractChanged(detail: "companion /resolve-address missing url field")
        }

        let expiresAt: Date
        if let expiry = json["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiry)
        } else {
            expiresAt = Date().addingTimeInterval(300)
        }

        let resolvedAt: Date
        if let resolved = json["resolvedAt"] as? Double {
            resolvedAt = Date(timeIntervalSince1970: resolved)
        } else {
            resolvedAt = Date()
        }

        let supportsRange = json["supportsRangeRequests"] as? Bool ?? true

        return StreamAddress(
            url: url,
            renditionItag: itag,
            expiresAt: expiresAt,
            resolvedAt: resolvedAt,
            supportsRangeRequests: supportsRange
        )
    }

    // MARK: Private — networking

    private func fetch(url: URL, songID: SongID, stage: ResolutionStage) async throws(SourceError) -> Data {
        do {
            return try await withTimeout(networkTimeout, stage: stage) {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw SourceError.resolutionFailed(songID, stage: stage, detail: "companion returned non-HTTP response")
                }
                if http.statusCode == 404 {
                    throw SourceError.unknownItag(songID, itag: 0)
                }
                if http.statusCode != 200 {
                    throw SourceError.resolutionFailed(songID, stage: stage, detail: "companion HTTP \(http.statusCode)")
                }
                return data
            }
        } catch let e as SourceError {
            throw e
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw SourceError.offline
            case .timedOut:
                throw SourceError.timeout(stage: stage)
            case .cancelled:
                throw SourceError.cancelled
            default:
                throw SourceError.resolutionFailed(songID, stage: stage, detail: "URLError \(urlError.code.rawValue)")
            }
        } catch {
            throw SourceError.resolutionFailed(songID, stage: stage, detail: "unexpected: \(type(of: error))")
        }
    }

    private func requireBaseURL(songID: SongID) throws(SourceError) -> URL {
        guard let base = baseURL else {
            throw SourceError.resolutionFailed(
                songID,
                stage: .fetchingPage,
                detail: "no companion address configured"
            )
        }
        return base
    }

    // MARK: Private — timeout

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
                throw SourceError.resolutionFailed("unknown", stage: stage, detail: "timeout group produced no result")
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: Private — mapping

    private func mapContainer(_ raw: String) -> Container {
        switch raw {
        case "m4a": return .m4a
        case "webm": return .webm
        case "mp4": return .mp4
        default: return .other(raw)
        }
    }

    private func mapCodec(_ raw: String) -> Codec {
        switch raw {
        case "aac": return .aac
        case "opus": return .opus
        case "vorbis": return .vorbis
        default: return .other(raw)
        }
    }
}

// MARK: - JSONSerialization convenience

private extension JSONSerialization {
    static func jsonObject(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [])
    }
}
