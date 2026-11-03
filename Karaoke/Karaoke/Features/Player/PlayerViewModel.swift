// T101 — PlayerViewModel.
//
// Regenerates suggestions whenever the current song changes and never caches
// across songs — the exclusion set changes every few minutes, so a cached list
// is a stale list (recommendation-provider.md Behavioural requirement 4).
//
// Satisfies: FR-025a … FR-025f

import Foundation
import Observation
import SwiftData

// MARK: - PlayerViewModel

/// Drives the player screen and the suggestions panel.
///
/// Suggestions are regenerated on every song change. No cross-song caching —
/// the exclusion set (performedSongIDs) changes every few minutes.
@MainActor
@Observable
final class PlayerViewModel {

    // MARK: Published state

    /// Current suggestions state (T100).
    private(set) var suggestionsState: SuggestionsState = .idle

    // MARK: Dependencies

    private let session: PlaybackSession
    private let engine: BlendedRecommendationEngine
    private let modelContext: ModelContext

    // MARK: Internal state

    /// The song ID for which suggestions were last fetched.
    /// Used to detect song changes and avoid redundant fetches.
    private var lastFetchedSongID: String?

    /// The active suggestion fetch task. Cancelled when the song changes.
    private var fetchTask: Task<Void, Never>?

    // MARK: Init

    init(
        session: PlaybackSession,
        engine: BlendedRecommendationEngine,
        modelContext: ModelContext
    ) {
        self.session = session
        self.engine = engine
        self.modelContext = modelContext
    }

    // MARK: Song change handling (T101)

    /// Called when the current song changes.
    ///
    /// Cancels any in-flight fetch and starts a new one. Never caches across
    /// songs — the exclusion set changes every few minutes.
    func onSongChanged(to newSongID: String?) {
        guard newSongID != lastFetchedSongID else { return }

        // Cancel the previous fetch — its results are stale.
        fetchTask?.cancel()
        fetchTask = nil
        lastFetchedSongID = newSongID

        guard let songID = newSongID else {
            suggestionsState = .idle
            return
        }

        suggestionsState = .loading
        fetchTask = Task { [weak self] in
            await self?.fetchSuggestions(for: songID)
        }
    }

    // MARK: Private — fetch

    private func fetchSuggestions(for songID: String) async {
        guard !Task.isCancelled else { return }

        // Build the exclusion context from the live session state.
        let context = ExclusionContext(
            currentSongID: songID,
            performedSongIDs: session.performedSongIDs,
            waitingQueueSongIDs: waitingQueueSongIDs(),
            contentFailedSongIDs: []
        )

        let results = await engine.suggestions(for: songID, context: context, limit: 10)

        guard !Task.isCancelled else { return }

        if results.isEmpty {
            // Distinguish cold start from a loaded-but-empty result.
            suggestionsState = isColdStart() ? .coldStart : .loaded([])
        } else {
            suggestionsState = .loaded(results)
        }
    }

    // MARK: Private — helpers

    /// Returns the set of song IDs currently queued as `waiting`.
    private func waitingQueueSongIDs() -> Set<String> {
        // #Predicate cannot reference enum cases directly; fetch all and filter.
        let descriptor = FetchDescriptor<QueueEntry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return Set(entries.filter { $0.state == .waiting }.map { $0.songID })
    }

    /// Cold start: no play history and no session co-occurrence data.
    private func isColdStart() -> Bool {
        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.playCount > 0 }
        )
        let playedCount = (try? modelContext.fetchCount(songDescriptor)) ?? 0
        let logDescriptor = FetchDescriptor<SessionLog>()
        let logCount = (try? modelContext.fetchCount(logDescriptor)) ?? 0
        return playedCount == 0 && logCount == 0
    }
}
