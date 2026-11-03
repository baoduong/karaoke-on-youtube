// T029 — SourceReference parsing.
//
// Accepts three input shapes:
//   1. Full URL:    https://www.youtube.com/watch?v=dQw4w9WgXcQ
//   2. Short URL:   https://youtu.be/dQw4w9WgXcQ
//   3. Bare ID:     dQw4w9WgXcQ
//
// Normalises to a SongID. Malformed input returns `malformedReference` with
// NO network call — this is a pure parse operation.

import Foundation

// MARK: - SourceReference

/// A parsed reference to a YouTube video, normalised to a SongID.
///
/// Parsing is pure — no network calls are made. A reference that cannot be
/// parsed yields `SourceError.malformedReference`.
struct SourceReference: Sendable, Equatable {

    /// The normalised upstream video identifier.
    let songID: SongID

    // MARK: Parsing

    /// Parse a user-supplied string into a SourceReference.
    ///
    /// Accepts:
    /// - Full watch URL:  `https://www.youtube.com/watch?v=<id>`
    /// - Short URL:       `https://youtu.be/<id>`
    /// - Bare identifier: `<id>` (exactly 11 chars of [A-Za-z0-9_-])
    ///
    /// - Parameter input: The raw string from the user.
    /// - Returns: A `SourceReference` with the normalised SongID.
    /// - Throws: `SourceError.malformedReference` if the input cannot be parsed.
    ///           No network call is made.
    static func parse(_ input: String) throws(SourceError) -> SourceReference {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SourceError.malformedReference(input)
        }

        // Try URL parsing first (handles both full and short URLs).
        if let url = URL(string: trimmed), url.scheme != nil {
            if let id = extractID(from: url) {
                return SourceReference(songID: id)
            }
            throw SourceError.malformedReference(input)
        }

        // Try bare identifier.
        if isValidYouTubeID(trimmed) {
            return SourceReference(songID: trimmed)
        }

        throw SourceError.malformedReference(input)
    }

    // MARK: Private helpers

    /// Extract a YouTube video ID from a URL.
    /// Returns nil if the URL is not a recognised YouTube URL shape.
    private static func extractID(from url: URL) -> SongID? {
        guard let host = url.host else { return nil }

        // Short URL: youtu.be/<id>
        if host == "youtu.be" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return isValidYouTubeID(path) ? path : nil
        }

        // Full URL: youtube.com/watch?v=<id>
        // Also handles: m.youtube.com, www.youtube.com, music.youtube.com
        let isYouTubeDomain = host == "youtube.com"
            || host == "www.youtube.com"
            || host == "m.youtube.com"
            || host == "music.youtube.com"

        guard isYouTubeDomain else { return nil }

        // /watch?v=<id>
        if url.path == "/watch" || url.path.hasPrefix("/watch") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let vItem = components.queryItems?.first(where: { $0.name == "v" }),
               let id = vItem.value,
               isValidYouTubeID(id) {
                return id
            }
        }

        // /shorts/<id>
        if url.path.hasPrefix("/shorts/") {
            let id = String(url.path.dropFirst("/shorts/".count))
                .components(separatedBy: "/").first ?? ""
            return isValidYouTubeID(id) ? id : nil
        }

        // /embed/<id>
        if url.path.hasPrefix("/embed/") {
            let id = String(url.path.dropFirst("/embed/".count))
                .components(separatedBy: "/").first ?? ""
            return isValidYouTubeID(id) ? id : nil
        }

        // /v/<id>
        if url.path.hasPrefix("/v/") {
            let id = String(url.path.dropFirst("/v/".count))
                .components(separatedBy: "/").first ?? ""
            return isValidYouTubeID(id) ? id : nil
        }

        return nil
    }

    /// Returns true when `id` matches the YouTube video identifier shape:
    /// exactly 11 characters from [A-Za-z0-9_-].
    static func isValidYouTubeID(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
