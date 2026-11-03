// T053, T054 — SearchViewModel.
//
// T053: Submit-driven search with per-session query caching.
//   NEVER keystroke-driven — the YouTube Data API quota is 100 searches/day
//   (research.md R2). Search-as-you-type would exhaust it in minutes.
//   Caching: the same query in the same session returns the cached result
//   without a network call.
//
// T054: Direct-reference entry.
//   A pasted URL or bare video ID resolves via SourceReference without a
//   search call (FR-002). This path never touches the search quota.
//
// Satisfies: FR-001, FR-002, FR-008

import Foundation
import Observation

// MARK: - SearchViewModel

/// View model for the search screen.
///
/// Search is submit-driven — the singer presses a button or the keyboard's
/// return key. Keystroke-driven search is explicitly forbidden because the
/// YouTube Data API quota is 100 calls per day (research.md R2).
///
/// Per-session query caching: the same query returns the cached result without
/// a network call. The cache is in-memory and cleared when the app is killed.
@MainActor
@Observable
final class SearchViewModel {

    // MARK: Published state

    /// The text the singer is typing. Bound to the search field.
    var queryText: String = ""

    /// The current search results.
    var results: [SongMetadata] = []

    /// True while a search or reference resolution is in progress.
    var isLoading: Bool = false

    /// The last error, if any. Cleared on the next successful operation.
    var lastError: SearchError?

    /// The result selected by the singer, ready for the player to load.
    var selectedSong: SongMetadata?

    // MARK: Dependencies

    private let router: SourceProviderRouter

    // MARK: Per-session query cache (T053)

    /// Cache: query string → results. In-memory, cleared on app kill.
    ///
    /// The same query in the same session returns the cached result without a
    /// network call. This is the primary quota-conservation mechanism alongside
    /// submit-only triggering.
    private var queryCache: [String: [SongMetadata]] = [:]

    // MARK: Task management

    private var searchTask: Task<Void, Never>?

    // MARK: Init

    init(router: SourceProviderRouter) {
        self.router = router
    }

    // MARK: Search (T053)

    /// Execute a search for the current `queryText`.
    ///
    /// Called only on explicit submit (button tap or keyboard return). Never
    /// called on every keystroke — the quota is 100 searches/day.
    ///
    /// Returns cached results immediately when the same query was already
    /// searched this session.
    func submitSearch() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // Cancel any in-flight search.
        searchTask?.cancel()

        searchTask = Task {
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        // Return cached result immediately — no network call.
        if let cached = queryCache[query] {
            results = cached
            lastError = nil
            return
        }

        isLoading = true
        lastError = nil

        do {
            let found = try await router.search(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            results = found
            queryCache[query] = found
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            lastError = SearchError(sourceError: error)
        }

        isLoading = false
    }

    // MARK: Direct reference (T054, FR-002)

    /// Resolve a pasted URL or bare video ID without a search call.
    ///
    /// This path never touches the search quota — it calls `metadata(for:)`,
    /// not `search(query:limit:)`. The result is presented as a single-item
    /// result list so the singer can select it the same way as a search result.
    func resolveDirectReference() {
        let input = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // Only attempt direct resolution if the input looks like a URL or ID.
        // If it does not parse, fall through to a regular search.
        guard let reference = try? SourceReference.parse(input) else {
            // Not a valid reference — treat as a search query.
            submitSearch()
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            await performDirectResolution(reference: reference)
        }
    }

    private func performDirectResolution(reference: SourceReference) async {
        isLoading = true
        lastError = nil

        do {
            let metadata = try await router.metadata(for: reference)
            guard !Task.isCancelled else { return }
            results = [metadata]
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            lastError = SearchError(sourceError: error)
        }

        isLoading = false
    }

    // MARK: Selection

    /// The singer selected a result. Passes it to the player.
    func select(_ song: SongMetadata) {
        selectedSong = song
    }

    // MARK: Cache management

    /// Clear the per-session query cache.
    ///
    /// Called when the singer explicitly wants fresh results (e.g., pull-to-refresh).
    func clearCache() {
        queryCache.removeAll()
    }
}

// MARK: - SearchError

/// A search error presented to the singer.
///
/// Distinguishes content-side failures (the singer's problem) from
/// mechanism-side failures (the maintainer's problem), per FR-008.
struct SearchError: Sendable {
    let message: String
    let isMechanismSide: Bool

    init(sourceError: SourceError) {
        switch sourceError {
        case .notFound, .private_, .removed, .regionBlocked, .ageRestricted,
             .liveStreamUnsupported, .noAudioRenditions:
            message = "This video is not available."
            isMechanismSide = false

        case .quotaExhausted:
            message = "Search limit reached for today. Try again tomorrow or paste a direct link."
            isMechanismSide = false

        case .offline:
            message = "No network connection. Check your connection and try again."
            isMechanismSide = false

        case .rateLimited:
            message = "Too many requests. Please wait a moment and try again."
            isMechanismSide = false

        case .malformedReference(let input):
            message = "'\(input)' is not a valid YouTube link or video ID."
            isMechanismSide = false

        case .resolutionFailed, .upstreamContractChanged, .cipherFailure:
            message = "Search is temporarily unavailable. The resolution mechanism may need updating."
            isMechanismSide = true

        case .timeout:
            message = "The request timed out. Check your connection and try again."
            isMechanismSide = false

        case .cancelled, .unknownItag:
            message = "Search was cancelled."
            isMechanismSide = false
        }
    }
}
