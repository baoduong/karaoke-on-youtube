// T073 — LRCLIBProvider.
//
// Fetches synchronized lyrics from lrclib.net.
//
// Verified facts from research.md R5 (Spike S6, 2026-11-03):
// - GET /api/get?artist_name=&track_name=&duration= returns 200, ~0.4s, no auth.
// - /api/get-cached does NOT exist (404). Do not call it.
// - Fall back to /api/search with client-side duration filtering.
// - hasWordSync is false on almost all tracks; line-level is the feature.
// - Response fields: id, trackName, artistName, albumName, duration (float s),
//   instrumental, hasWordSync, plainLyrics, syncedLyrics, lyricsfile.
//
// Disabled by default — the singer opts in (FR-022, contracts/lyrics-provider.md).
//
// Satisfies: FR-022, contracts/lyrics-provider.md

import Foundation

// MARK: - LRCLIBProvider

/// Fetches synchronized lyrics from lrclib.net.
///
/// Disabled until the singer enables it (`isEnabled` defaults to false).
/// No network request is made while disabled (contracts/lyrics-provider.md
/// Behavioural requirements).
final class LRCLIBProvider: LyricsProvider, @unchecked Sendable {

    // MARK: LyricsProvider

    let identifier = LyricsProviderID.lrclib

    /// Whether the singer has enabled this provider.
    /// Defaults to false — no network request is made until the singer opts in.
    var isEnabled: Bool

    // MARK: Dependencies

    private let session: URLSession
    private let parser: LyricsParser

    // MARK: Constants

    private static let baseURL = "https://lrclib.net/api"
    /// Duration tolerance in seconds for client-side filtering (search fallback).
    /// A track whose duration differs by more than this is almost certainly the wrong song.
    private static let durationToleranceSeconds: Double = 10

    // MARK: Init

    init(isEnabled: Bool = false, session: URLSession = .shared) {
        self.isEnabled = isEnabled
        self.session = session
        self.parser = LyricsParser()
    }

    // MARK: LyricsProvider

    func lyrics(for query: LyricsQuery) async throws(LyricsError) -> LyricsTrackData? {
        guard isEnabled else { return nil }

        // Try the exact lookup first (research.md R5: /api/get works).
        if let track = try await exactLookup(query: query) {
            return track
        }

        // Fall back to search with client-side duration filtering.
        return try await searchFallback(query: query)
    }

    // MARK: Private — exact lookup

    private func exactLookup(query: LyricsQuery) async throws(LyricsError) -> LyricsTrackData? {
        var components = URLComponents(string: "\(Self.baseURL)/get")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "duration", value: String(query.durationSeconds))
        ]
        if let artist = query.artist {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw LyricsError.providerUnavailable(detail: "Could not build /api/get URL")
        }

        let response = try await fetch(url: url)

        // 404 means not found — return nil, not an error.
        if response.statusCode == 404 { return nil }

        guard response.statusCode == 200 else {
            if response.statusCode == 429 {
                throw LyricsError.rateLimited(retryAfter: nil)
            }
            throw LyricsError.providerUnavailable(detail: "HTTP \(response.statusCode) from /api/get")
        }

        guard let result = try decodeResult(data: response.data) else { return nil }
        return parseResult(result, songID: query.title, durationSeconds: query.durationSeconds)
    }

    // MARK: Private — search fallback

    private func searchFallback(query: LyricsQuery) async throws(LyricsError) -> LyricsTrackData? {
        var components = URLComponents(string: "\(Self.baseURL)/search")
        var items: [URLQueryItem] = [URLQueryItem(name: "q", value: query.title)]
        if let artist = query.artist {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw LyricsError.providerUnavailable(detail: "Could not build /api/search URL")
        }

        let response = try await fetch(url: url)

        guard response.statusCode == 200 else {
            if response.statusCode == 429 {
                throw LyricsError.rateLimited(retryAfter: nil)
            }
            throw LyricsError.providerUnavailable(detail: "HTTP \(response.statusCode) from /api/search")
        }

        let results = try decodeResults(data: response.data)

        // Client-side duration filtering — the duration check is what makes the
        // feature usable (contracts/lyrics-provider.md, LyricsQuery.durationSeconds).
        let targetDuration = Double(query.durationSeconds)
        let matched = results.first { result in
            guard let d = result.duration else { return false }
            return abs(d - targetDuration) <= Self.durationToleranceSeconds
        }

        guard let matched else { return nil }
        return parseResult(matched, songID: query.title, durationSeconds: query.durationSeconds)
    }

    // MARK: Private — networking

    private struct HTTPResponse {
        let statusCode: Int
        let data: Data
    }

    private func fetch(url: URL) async throws(LyricsError) -> HTTPResponse {
        do {
            let (data, response) = try await session.data(from: url)
            let http = response as? HTTPURLResponse
            return HTTPResponse(statusCode: http?.statusCode ?? 0, data: data)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw LyricsError.offline
            case .timedOut:
                throw LyricsError.timeout
            default:
                throw LyricsError.providerUnavailable(detail: urlError.localizedDescription)
            }
        } catch {
            throw LyricsError.providerUnavailable(detail: error.localizedDescription)
        }
    }

    // MARK: Private — decoding

    private struct LRCLIBResult: Decodable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let hasWordSync: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private func decodeResult(data: Data) throws(LyricsError) -> LRCLIBResult? {
        do {
            return try JSONDecoder().decode(LRCLIBResult.self, from: data)
        } catch {
            throw LyricsError.malformedResponse(detail: "JSON decode failed: \(error.localizedDescription)")
        }
    }

    private func decodeResults(data: Data) throws(LyricsError) -> [LRCLIBResult] {
        do {
            return try JSONDecoder().decode([LRCLIBResult].self, from: data)
        } catch {
            throw LyricsError.malformedResponse(detail: "JSON decode failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private — parsing

    private func parseResult(
        _ result: LRCLIBResult,
        songID: String,
        durationSeconds: Int
    ) -> LyricsTrackData? {
        // Instrumental tracks have no lyrics — return nil, not an error.
        if result.instrumental == true { return nil }

        // Prefer synced lyrics; fall back to plain (which has no timing).
        guard let syncedLyrics = result.syncedLyrics, !syncedLyrics.isEmpty else {
            return nil
        }

        let hasWordSync = result.hasWordSync ?? false

        // Parse and validate. Rejection yields nil (contracts/lyrics-provider.md Parsing).
        return parser.parse(
            lrc: syncedLyrics,
            songID: songID,
            source: .lrclib,
            hasWordSync: hasWordSync,
            songDurationSeconds: durationSeconds
        )
    }
}
