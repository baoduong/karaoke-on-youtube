// T093 — Local recommendation strategies.
//
// coOccurrence: songs sung in the same past session as the current song.
// history:      previously sung, ranked by play count and recency.
// favourite:    an unplayed favourite.
//
// These three strategies are the backbone — they never fail, never require a
// network, and never spend search quota. Together they guarantee FR-025b for
// any singer who has used the app for more than a few songs.
//
// Satisfies: FR-025a, FR-025b, FR-025f

import Foundation
import SwiftData

// MARK: - CoOccurrenceStrategy

/// Songs sung in the same past session as the current song.
///
/// Captures this group's actual taste — a signal no content-based approach can
/// replicate. One local query, never fails.
struct CoOccurrenceStrategy: RecommendationProvider, @unchecked Sendable {

    let identifier: StrategyID = "coOccurrence"
    let isAvailable: Bool = true

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func candidates(for songID: SuggestionSongID,
                    limit: Int) async throws(RecommendationError) -> [Suggestion] {
        // Count how many sessions each co-occurring song appeared in with songID.
        var coOccurrenceCounts: [String: Int] = [:]

        let logs: [SessionLog]
        do {
            logs = try modelContext.fetch(FetchDescriptor<SessionLog>())
        } catch {
            return []
        }

        for log in logs {
            let coOccurred = log.coOccurrences(with: songID)
            for id in coOccurred {
                coOccurrenceCounts[id, default: 0] += 1
            }
        }

        guard !coOccurrenceCounts.isEmpty else { return [] }

        let maxCount = Double(coOccurrenceCounts.values.max() ?? 1)

        return coOccurrenceCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key // deterministic tie-break
            }
            .prefix(limit)
            .map { id, count in
                Suggestion(
                    songID: id,
                    strategy: .coOccurrence,
                    score: Double(count) / maxCount
                )
            }
    }
}

// MARK: - HistoryStrategy

/// Previously sung songs, ranked by play count and recency.
///
/// Scores by combining play count (primary) and recency (secondary).
struct HistoryStrategy: RecommendationProvider, @unchecked Sendable {

    let identifier: StrategyID = "history"
    let isAvailable: Bool = true

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func candidates(for songID: SuggestionSongID,
                    limit: Int) async throws(RecommendationError) -> [Suggestion] {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.playCount > 0 && $0.id != songID },
            sortBy: [SortDescriptor(\.playCount, order: .reverse)]
        )

        let songs: [Song]
        do {
            songs = try modelContext.fetch(descriptor)
        } catch {
            return []
        }

        guard !songs.isEmpty else { return [] }

        let maxPlayCount = Double(songs.first?.playCount ?? 1)
        let now = Date()

        return songs
            .prefix(limit)
            .map { song in
                let playScore = Double(song.playCount) / maxPlayCount
                let recencyScore: Double
                if let lastPlayed = song.lastPlayedAt {
                    // Decay over 30 days: 1.0 at 0 days, ~0.0 at 30 days.
                    let daysSince = now.timeIntervalSince(lastPlayed) / 86400
                    recencyScore = max(0, 1.0 - daysSince / 30.0)
                } else {
                    recencyScore = 0
                }
                // Weight play count 70%, recency 30%.
                let score = 0.7 * playScore + 0.3 * recencyScore
                return Suggestion(
                    songID: song.id,
                    strategy: .history,
                    score: min(1.0, max(0.0, score))
                )
            }
    }
}

// MARK: - FavouriteStrategy

/// An unplayed favourite — a song the singer marked but has not sung this session.
///
/// Score is based on how recently it was added (newest favourites first).
struct FavouriteStrategy: RecommendationProvider, @unchecked Sendable {

    let identifier: StrategyID = "favourite"
    let isAvailable: Bool = true

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func candidates(for songID: SuggestionSongID,
                    limit: Int) async throws(RecommendationError) -> [Suggestion] {
        let descriptor = FetchDescriptor<Favourite>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )

        let favourites: [Favourite]
        do {
            favourites = try modelContext.fetch(descriptor)
        } catch {
            return []
        }

        let eligible = favourites.filter { $0.songID != songID }
        guard !eligible.isEmpty else { return [] }

        let count = Double(eligible.count)

        return eligible
            .prefix(limit)
            .enumerated()
            .map { index, fav in
                // Newest favourite scores 1.0, oldest scores near 0.
                let score = 1.0 - Double(index) / count
                return Suggestion(
                    songID: fav.songID,
                    strategy: .favourite,
                    score: score
                )
            }
    }
}
