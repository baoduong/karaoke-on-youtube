// T052 — DataAPISearchProvider.
//
// Calls the YouTube Data API v3 search.list and videos.list endpoints.
//
// This provider DOES supply channelName and durationSeconds — OnDeviceSourceProvider
// cannot (it has no access to those fields via YouTubeKit). The router places this
// provider first for search and metadata, and falls through to OnDeviceSourceProvider
// for rendition resolution and stream addresses.
//
// API key is read from a local configuration file (Karaoke/Karaoke/Config.plist,
// key "YouTubeDataAPIKey"). An absent or empty key makes this provider unhealthy
// rather than crashing — the router falls through to OnDeviceSourceProvider for
// operations it can handle.
//
// Quota: 100 search units per day (research.md R2). This provider is NEVER called
// keystroke-by-keystroke — only on explicit submit (T053).
//
// Satisfies: FR-001, FR-002, FR-008

import Foundation

// MARK: - DataAPISearchProvider

/// Calls the YouTube Data API v3 for search and metadata.
///
/// Supplies `channelName` and `durationSeconds` that OnDeviceSourceProvider
/// cannot provide. Does NOT resolve renditions or stream addresses — those
/// require the on-device provider.
///
/// An absent API key makes this provider report `.unhealthy` rather than
/// crashing. The router falls through to OnDeviceSourceProvider for operations
/// it can handle without a key.
final class DataAPISearchProvider: SourceProvider, @unchecked Sendable {

    let identifier = SourceProviderID(rawValue: "youtube-data-api")

    // MARK: Configuration

    private let apiKey: String?
    private let session: URLSession
    private let networkTimeout: TimeInterval = 15

    private static let baseURL = "https://www.googleapis.com/youtube/v3"

    /// Read the API key from Config.plist in the app bundle.
    ///
    /// The key is stored in a local config file that is gitignored, so it is
    /// never committed to the repository. An absent key makes this provider
    /// unhealthy rather than crashing (T052 requirement).
    init(session: URLSession = .shared) {
        self.session = session
        self.apiKey = Self.readAPIKey()
    }

    private static func readAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let key = dict["YouTubeDataAPIKey"] as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }

    // MARK: SourceProvider — Health

    func healthCheck() async -> ProviderHealth {
        guard let key = apiKey, !key.isEmpty else {
            return .unhealthy(reason: "YouTubeDataAPIKey absent from Config.plist")
        }
        return .healthy
    }

    // MARK: SourceProvider — Search (FR-001)

    /// Search YouTube for karaoke sources using the Data API v3 search.list endpoint.
    ///
    /// Returns title, channelName, and durationSeconds per result (FR-001).
    /// Never called keystroke-by-keystroke — only on explicit submit (T053).
    func search(query: String, limit: Int) async throws(SourceError) -> [SongMetadata] {
        guard let key = apiKey else {
            throw SourceError.resolutionFailed(
                query,
                stage: .fetchingPage,
                detail: "YouTubeDataAPIKey not configured"
            )
        }

        guard !Task.isCancelled else { throw SourceError.cancelled }

        // Step 1: search.list — returns video IDs and basic metadata.
        let searchResults = try await performSearch(query: query, limit: limit, apiKey: key)

        guard !Task.isCancelled else { throw SourceError.cancelled }

        // Step 2: videos.list — enriches with duration (ISO 8601) and channel name.
        let videoIDs = searchResults.map { $0.id }
        guard !videoIDs.isEmpty else { return [] }

        let enriched = try await fetchVideoDetails(ids: videoIDs, apiKey: key)

        // Merge: search results provide order; video details provide duration.
        return searchResults.compactMap { item in
            guard let detail = enriched[item.id] else { return nil }
            return SongMetadata(
                id: item.id,
                title: item.title,
                channelName: item.channelName,
                durationSeconds: detail.durationSeconds,
                thumbnailURL: item.thumbnailURL
            )
        }
    }

    // MARK: SourceProvider — Metadata (FR-002)

    /// Resolve a direct reference to metadata using videos.list.
    ///
    /// Supplies channelName and durationSeconds that OnDeviceSourceProvider cannot.
    func metadata(for reference: SourceReference) async throws(SourceError) -> SongMetadata {
        guard let key = apiKey else {
            throw SourceError.resolutionFailed(
                reference.songID,
                stage: .fetchingPage,
                detail: "YouTubeDataAPIKey not configured"
            )
        }

        guard !Task.isCancelled else { throw SourceError.cancelled }

        let details = try await fetchVideoDetails(ids: [reference.songID], apiKey: key)

        guard let detail = details[reference.songID] else {
            throw SourceError.notFound(reference.songID)
        }

        return SongMetadata(
            id: reference.songID,
            title: detail.title,
            channelName: detail.channelName,
            durationSeconds: detail.durationSeconds,
            thumbnailURL: detail.thumbnailURL
        )
    }

    // MARK: SourceProvider — Renditions (not supported)

    /// This provider cannot resolve renditions — it has no access to stream URLs.
    ///
    /// Throws a mechanism-side error so the router falls through to
    /// OnDeviceSourceProvider, which can resolve renditions via YouTubeKit.
    func audioRenditions(for songID: SongID) async throws(SourceError) -> [AudioRendition] {
        throw SourceError.resolutionFailed(
            songID,
            stage: .parsingFormats,
            detail: "Data API provider cannot resolve renditions; route to on-device provider"
        )
    }

    /// This provider cannot produce stream addresses.
    func streamAddress(for songID: SongID, itag: Int) async throws(SourceError) -> StreamAddress {
        throw SourceError.resolutionFailed(
            songID,
            stage: .buildingAddress,
            detail: "Data API provider cannot produce stream addresses; route to on-device provider"
        )
    }

    // MARK: Private — search.list

    private struct SearchItem {
        let id: SongID
        let title: String
        let channelName: String
        let thumbnailURL: URL?
    }

    private func performSearch(
        query: String,
        limit: Int,
        apiKey: String
    ) async throws(SourceError) -> [SearchItem] {
        var components = URLComponents(string: "\(Self.baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoCategoryId", value: "10"), // Music
            URLQueryItem(name: "maxResults", value: String(min(limit, 50))),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw SourceError.resolutionFailed(query, stage: .fetchingPage, detail: "invalid search URL")
        }

        let data = try await fetch(url: url, songID: query, stage: .fetchingPage)
        return try parseSearchResponse(data: data, songID: query)
    }

    private func parseSearchResponse(data: Data, songID: String) throws(SourceError) -> [SearchItem] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                throw SourceError.upstreamContractChanged(detail: "search.list response missing 'items'")
            }

            return items.compactMap { item -> SearchItem? in
                guard let idDict = item["id"] as? [String: Any],
                      let videoID = idDict["videoId"] as? String,
                      SourceReference.isValidYouTubeID(videoID),
                      let snippet = item["snippet"] as? [String: Any],
                      let title = snippet["title"] as? String,
                      let channelTitle = snippet["channelTitle"] as? String else {
                    return nil
                }

                let thumbnailURL: URL? = {
                    guard let thumbnails = snippet["thumbnails"] as? [String: Any],
                          let medium = thumbnails["medium"] as? [String: Any],
                          let urlString = medium["url"] as? String else {
                        return nil
                    }
                    return URL(string: urlString)
                }()

                return SearchItem(
                    id: videoID,
                    title: title,
                    channelName: channelTitle,
                    thumbnailURL: thumbnailURL
                )
            }
        } catch let sourceError as SourceError {
            throw sourceError
        } catch {
            throw SourceError.resolutionFailed(songID, stage: .parsingPlayerResponse, detail: "JSON parse error")
        }
    }

    // MARK: Private — videos.list

    private struct VideoDetail {
        let title: String
        let channelName: String
        let durationSeconds: Int
        let thumbnailURL: URL?
    }

    private func fetchVideoDetails(
        ids: [SongID],
        apiKey: String
    ) async throws(SourceError) -> [SongID: VideoDetail] {
        var components = URLComponents(string: "\(Self.baseURL)/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw SourceError.resolutionFailed(
                ids.first ?? "unknown",
                stage: .fetchingPage,
                detail: "invalid videos URL"
            )
        }

        let data = try await fetch(url: url, songID: ids.first ?? "unknown", stage: .parsingPlayerResponse)
        return try parseVideosResponse(data: data)
    }

    private func parseVideosResponse(data: Data) throws(SourceError) -> [SongID: VideoDetail] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                throw SourceError.upstreamContractChanged(detail: "videos.list response missing 'items'")
            }

            var result: [SongID: VideoDetail] = [:]
            for item in items {
                guard let videoID = item["id"] as? String,
                      let snippet = item["snippet"] as? [String: Any],
                      let contentDetails = item["contentDetails"] as? [String: Any],
                      let title = snippet["title"] as? String,
                      let channelTitle = snippet["channelTitle"] as? String,
                      let durationISO = contentDetails["duration"] as? String else {
                    continue
                }

                let durationSeconds = parseISO8601Duration(durationISO)
                // durationSeconds == 0 means the metadata is unusable — Song validation
                // will reject it. Do not invent a value (tasks.md MUST NOT DO).
                guard durationSeconds > 0 else { continue }

                let thumbnailURL: URL? = {
                    guard let thumbnails = snippet["thumbnails"] as? [String: Any],
                          let medium = thumbnails["medium"] as? [String: Any],
                          let urlString = medium["url"] as? String else {
                        return nil
                    }
                    return URL(string: urlString)
                }()

                result[videoID] = VideoDetail(
                    title: title,
                    channelName: channelTitle,
                    durationSeconds: durationSeconds,
                    thumbnailURL: thumbnailURL
                )
            }
            return result
        } catch let sourceError as SourceError {
            throw sourceError
        } catch {
            throw SourceError.upstreamContractChanged(detail: "videos.list JSON parse error")
        }
    }

    // MARK: Private — ISO 8601 duration parser

    /// Parse an ISO 8601 duration string (e.g. "PT4M13S") to seconds.
    ///
    /// Returns 0 when the string cannot be parsed — Song validation will reject
    /// the result rather than persisting a zero duration (data-model.md).
    private func parseISO8601Duration(_ iso: String) -> Int {
        // Pattern: PT[nH][nM][nS]
        var seconds = 0
        var current = ""
        for char in iso {
            if char.isNumber {
                current.append(char)
            } else if char == "H", let hours = Int(current) {
                seconds += hours * 3600
                current = ""
            } else if char == "M", let minutes = Int(current) {
                seconds += minutes * 60
                current = ""
            } else if char == "S", let secs = Int(current) {
                seconds += secs
                current = ""
            }
        }
        return seconds
    }

    // MARK: Private — HTTP fetch

    private func fetch(url: URL, songID: String, stage: ResolutionStage) async throws(SourceError) -> Data {
        guard !Task.isCancelled else { throw SourceError.cancelled }

        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SourceError.resolutionFailed(songID, stage: stage, detail: "non-HTTP response")
            }

            switch httpResponse.statusCode {
            case 200:
                return data
            case 403:
                // Could be quota exhausted or API key invalid.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let errors = error["errors"] as? [[String: Any]],
                   let reason = errors.first?["reason"] as? String,
                   reason == "quotaExceeded" || reason == "dailyLimitExceeded" {
                    throw SourceError.quotaExhausted(resetAt: nil)
                }
                throw SourceError.resolutionFailed(songID, stage: stage, detail: "HTTP 403")
            case 404:
                throw SourceError.notFound(songID)
            case 429:
                throw SourceError.rateLimited(retryAfter: nil)
            default:
                throw SourceError.resolutionFailed(
                    songID,
                    stage: stage,
                    detail: "HTTP \(httpResponse.statusCode)"
                )
            }
        } catch let sourceError as SourceError {
            throw sourceError
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
            if error is CancellationError {
                throw SourceError.cancelled
            }
            throw SourceError.resolutionFailed(songID, stage: stage, detail: "unexpected error")
        }
    }
}
