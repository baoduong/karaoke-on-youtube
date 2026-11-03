import Foundation
import SwiftData

/// The platform's own "what's next" list, read through the companion service.
///
/// There is no public API for this. The web client embeds the list in the
/// watch page and pages it through a private endpoint, so the companion parses
/// that page. Keeping the parse server-side is the whole point: YouTube
/// recently renamed these entries from `compactVideoRenderer` to
/// `lockupViewModel`, silently breaking every consumer written against the old
/// name. When the next rename lands, the fix is a file edit on the singer's own
/// machine rather than a rebuild and a re-signing by hand.
///
/// This sits at priority 1 but is the only strategy that can fail. Its absence
/// must be unremarkable, and it is: four local strategies carry the feature.
struct UpstreamRelatedStrategy: RecommendationProvider, @unchecked Sendable {

    let identifier: StrategyID = "upstreamRelated"

    private let modelContext: ModelContext
    private let session: URLSession

    init(modelContext: ModelContext, session: URLSession = .shared) {
        self.modelContext = modelContext
        self.session = session
    }

    /// Available only when a companion address is configured. Without one
    /// there is nothing to ask, which is a normal state rather than a fault.
    var isAvailable: Bool {
        CompanionSourceProvider.configuredAddress != nil
    }

    func candidates(
        for songID: SuggestionSongID,
        limit: Int
    ) async throws(RecommendationError) -> [Suggestion] {
        guard let url = Self.relatedURL(songID: songID, limit: limit) else {
            throw .strategyUnavailable
        }

        let payload: [[String: Any]]
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw RecommendationError.upstreamFailed(detail: "companion /related returned non-200")
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]]
            else {
                throw RecommendationError.upstreamFailed(detail: "companion /related returned an unusable shape")
            }
            payload = results
        } catch let error as RecommendationError {
            throw error
        } catch {
            throw .upstreamFailed(detail: error.localizedDescription)
        }

        return await MainActor.run { persistAndRank(payload, limit: limit) }
    }

    /// Writes each candidate's metadata into the store before returning it.
    ///
    /// The suggestion row looks its title and channel up from the store by id.
    /// A related video has never been searched for, so without this step it
    /// would render as a bare video id with no channel and no duration.
    @MainActor
    private func persistAndRank(_ payload: [[String: Any]], limit: Int) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        for (index, raw) in payload.enumerated() {
            guard let id = raw["id"] as? String, !id.isEmpty,
                  let title = raw["title"] as? String, !title.isEmpty,
                  let duration = raw["durationSeconds"] as? Int, duration > 0
            else {
                continue
            }

            let channel = (raw["channelName"] as? String) ?? "Unknown"
            upsertSong(id: id, title: title, channel: channel, duration: duration,
                       thumbnail: (raw["thumbnailURL"] as? String).flatMap(URL.init(string:)))

            // Position in the upstream list is the only ranking signal on
            // offer, so the first entry scores highest.
            let score = 1.0 - (Double(index) / Double(max(payload.count, 1)))
            suggestions.append(
                Suggestion(songID: id, strategy: .upstreamRelated, score: max(0, min(1, score)))
            )

            if suggestions.count >= limit { break }
        }

        try? modelContext.save()
        return suggestions
    }

    @MainActor
    private func upsertSong(id: String, title: String, channel: String, duration: Int, thumbnail: URL?) {
        var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if (try? modelContext.fetch(descriptor).first) != nil { return }

        modelContext.insert(
            Song(id: id, title: title, channelName: channel, durationSeconds: duration, thumbnailURL: thumbnail)
        )
    }

    static func relatedURL(songID: String, limit: Int) -> URL? {
        guard let base = CompanionSourceProvider.configuredAddress,
              var components = URLComponents(
                url: base.appendingPathComponent("related"),
                resolvingAgainstBaseURL: false
              )
        else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "id", value: songID),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return components.url
    }
}
