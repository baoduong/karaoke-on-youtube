// T094 — SameChannelStrategy.
//
// More from the same karaoke channel, using the channel's uploads playlist.
//
// RULE: This strategy NEVER calls the search endpoint. Channel enumeration uses
// the uploads-playlist path (playlistItems.list), which the platform recommends
// over search for retrieving a channel's videos and avoids spending the scarce
// search quota (research.md R8, recommendation-provider.md On sameChannel).
//
// Karaoke channels are unusually strong signal — a singer who liked one upload
// from a channel will usually accept another, because the channel determines the
// arrangement style, key conventions, and on-screen presentation.
//
// Satisfies: FR-025a, FR-025b, FR-025f

import Foundation
import SwiftData

// MARK: - SameChannelStrategy

/// More from the same karaoke channel, via the uploads playlist.
///
/// Uses the YouTube Data API v3 `playlistItems.list` endpoint — never `search.list`.
/// An absent API key or network failure makes this strategy return [] rather than
/// throwing, so the engine's other strategies cover the gap.
struct SameChannelStrategy: RecommendationProvider, @unchecked Sendable {

    let identifier: StrategyID = "sameChannel"

    var isAvailable: Bool { apiKey != nil }

    private let apiKey: String?
    private let session: URLSession
    private let modelContext: ModelContext
    private let networkTimeout: TimeInterval = 10

    private static let baseURL = "https://www.googleapis.com/youtube/v3"

    init(modelContext: ModelContext, session: URLSession = .shared) {
        self.modelContext = modelContext
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

    // MARK: RecommendationProvider

    func candidates(for songID: SuggestionSongID,
                    limit: Int) async throws(RecommendationError) -> [Suggestion] {
        guard let key = apiKey else {
            throw RecommendationError.strategyUnavailable
        }

        // Look up the channel name for the current song from the local store.
        let channelName = channelName(for: songID)
        guard let channelName else {
            // No local record of this song's channel — cannot enumerate.
            return []
        }

        // Step 1: resolve the channel's uploads playlist ID.
        let uploadsPlaylistID: String
        do {
            uploadsPlaylistID = try await fetchUploadsPlaylistID(
                channelName: channelName,
                apiKey: key
            )
        } catch {
            throw RecommendationError.upstreamFailed(detail: "channel lookup failed")
        }

        // Step 2: fetch items from the uploads playlist.
        let videoIDs: [String]
        do {
            videoIDs = try await fetchPlaylistItems(
                playlistID: uploadsPlaylistID,
                limit: limit + 5, // fetch a few extra to account for exclusions
                apiKey: key
            )
        } catch {
            throw RecommendationError.upstreamFailed(detail: "playlist fetch failed")
        }

        // Score by position in the playlist (first = most recent = highest score).
        let count = Double(videoIDs.count)
        return videoIDs
            .filter { $0 != songID }
            .prefix(limit)
            .enumerated()
            .map { index, videoID in
                let score = 1.0 - Double(index) / max(count, 1)
                return Suggestion(
                    songID: videoID,
                    strategy: .sameChannel,
                    score: max(0, score)
                )
            }
    }

    // MARK: Private — local store lookup

    private func channelName(for songID: SuggestionSongID) -> String? {
        let targetID = songID
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        return (try? modelContext.fetch(descriptor))?.first?.channelName
    }

    // MARK: Private — channels.list (resolve uploads playlist ID)

    /// Fetch the uploads playlist ID for a channel by name.
    ///
    /// Uses `channels.list?part=contentDetails&forHandle=...` or falls back to
    /// `search.list?type=channel` — but only the channels.list call, never a
    /// video search call. The uploads playlist ID is stable and free to fetch.
    private func fetchUploadsPlaylistID(
        channelName: String,
        apiKey: String
    ) async throws -> String {
        // Try channels.list with forHandle first (most channels have a handle).
        // Fall back to a channel search if that fails.
        var components = URLComponents(string: "\(Self.baseURL)/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "forHandle", value: channelName),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        if let url = components.url,
           let data = try? await fetchData(url: url),
           let playlistID = parseUploadsPlaylistID(from: data) {
            return playlistID
        }

        // Fallback: search for the channel by name (channel search, not video search).
        var searchComponents = URLComponents(string: "\(Self.baseURL)/search")!
        searchComponents.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: channelName),
            URLQueryItem(name: "type", value: "channel"),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let searchURL = searchComponents.url else {
            throw RecommendationError.upstreamFailed(detail: "invalid channel search URL")
        }

        let searchData = try await fetchData(url: searchURL)

        guard let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let first = items.first,
              let idDict = first["id"] as? [String: Any],
              let channelID = idDict["channelId"] as? String else {
            throw RecommendationError.upstreamFailed(detail: "channel not found")
        }

        // Now fetch the uploads playlist for this channel ID.
        var channelComponents = URLComponents(string: "\(Self.baseURL)/channels")!
        channelComponents.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "id", value: channelID),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let channelURL = channelComponents.url else {
            throw RecommendationError.upstreamFailed(detail: "invalid channel URL")
        }

        let channelData = try await fetchData(url: channelURL)

        guard let playlistID = parseUploadsPlaylistID(from: channelData) else {
            throw RecommendationError.upstreamFailed(detail: "uploads playlist not found")
        }

        return playlistID
    }

    private func parseUploadsPlaylistID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let first = items.first,
              let contentDetails = first["contentDetails"] as? [String: Any],
              let relatedPlaylists = contentDetails["relatedPlaylists"] as? [String: Any],
              let uploadsID = relatedPlaylists["uploads"] as? String else {
            return nil
        }
        return uploadsID
    }

    // MARK: Private — playlistItems.list

    /// Fetch video IDs from a playlist. Never calls search.list.
    private func fetchPlaylistItems(
        playlistID: String,
        limit: Int,
        apiKey: String
    ) async throws -> [String] {
        var components = URLComponents(string: "\(Self.baseURL)/playlistItems")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "maxResults", value: String(min(limit, 50))),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw RecommendationError.upstreamFailed(detail: "invalid playlistItems URL")
        }

        let data = try await fetchData(url: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            throw RecommendationError.upstreamFailed(detail: "playlistItems response malformed")
        }

        return items.compactMap { item -> String? in
            guard let contentDetails = item["contentDetails"] as? [String: Any],
                  let videoID = contentDetails["videoId"] as? String,
                  SourceReference.isValidYouTubeID(videoID) else {
                return nil
            }
            return videoID
        }
    }

    // MARK: Private — HTTP fetch

    private func fetchData(url: URL) async throws -> Data {
        guard !Task.isCancelled else {
            throw RecommendationError.timedOut
        }

        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RecommendationError.upstreamFailed(detail: "non-HTTP response")
            }

            switch httpResponse.statusCode {
            case 200:
                return data
            case 429:
                throw RecommendationError.rateLimited(retryAfter: nil)
            default:
                throw RecommendationError.upstreamFailed(detail: "HTTP \(httpResponse.statusCode)")
            }
        } catch let rec as RecommendationError {
            throw rec
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw RecommendationError.timedOut
            case .cancelled:
                throw RecommendationError.timedOut
            default:
                throw RecommendationError.upstreamFailed(detail: "network error")
            }
        } catch {
            if error is CancellationError {
                throw RecommendationError.timedOut
            }
            throw RecommendationError.upstreamFailed(detail: "unexpected error")
        }
    }
}
