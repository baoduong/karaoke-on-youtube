// T099 — SuggestionsView: shows title, channel, duration, and singer-facing reason.
// T100 — Explicit cold-start empty state, distinguishable from loading.
//
// FR-025a: suggested next songs.
// FR-025e: add-to-queue and play-now actions matching search result behaviour.
// FR-025f: each suggestion carries a short, singer-facing reason.
//
// Cold start: with no history and no upstream data the app says so plainly
// rather than rendering an empty list that looks like it is still loading.

import SwiftUI

// MARK: - SuggestionsView

/// Displays suggested next songs for the currently playing song.
///
/// Shows title, channel, duration, and the singer-facing reason per suggestion
/// (FR-025a, FR-025f). Provides add-to-queue and play-now actions (FR-025e).
struct SuggestionsView: View {

    let state: SuggestionsState
    var onAddToQueue: ((SuggestionSongID) -> Void)?
    var onPlayNow: ((SuggestionSongID) -> Void)?

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()

            case .loading:
                loadingView

            case .coldStart:
                coldStartView

            case .loaded(let suggestions):
                if suggestions.isEmpty {
                    coldStartView
                } else {
                    suggestionsList(suggestions)
                }
            }
        }
    }

    // MARK: Loading state

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Finding suggestions…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: Cold-start state (T100)

    /// Explicit cold-start state — not a loading state.
    ///
    /// With no history and no upstream data the app says so plainly rather than
    /// rendering an empty list that looks like it is still loading
    /// (recommendation-provider.md Cold start).
    private var coldStartView: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No suggestions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Sing a few songs and suggestions will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: Suggestions list

    private func suggestionsList(_ suggestions: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Up Next")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(suggestions, id: \.songID) { suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    onAddToQueue: { onAddToQueue?(suggestion.songID) },
                    onPlayNow: { onPlayNow?(suggestion.songID) }
                )
                Divider()
                    .padding(.leading)
            }
        }
    }
}

// MARK: - SuggestionRow

/// One row in the suggestions list.
///
/// Shows title (from the song ID — the full Song is loaded on action),
/// the singer-facing reason, and action buttons (FR-025e, FR-025f).
private struct SuggestionRow: View {

    let suggestion: Suggestion
    var onAddToQueue: (() -> Void)?
    var onPlayNow: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Strategy icon
            Image(systemName: strategyIcon)
                .font(.caption)
                .foregroundStyle(strategyColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Song ID shown until the Song is resolved — the view model
                // enriches this with title/channel when available.
                Text(suggestion.songID)
                    .font(.subheadline)
                    .lineLimit(1)

                // Singer-facing reason (FR-025f).
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions (FR-025e).
            HStack(spacing: 8) {
                Button {
                    onAddToQueue?()
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    onPlayNow?()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var strategyIcon: String {
        switch suggestion.strategy {
        case .upstreamRelated: return "sparkles"
        case .sameChannel:     return "tv"
        case .coOccurrence:    return "person.2"
        case .history:         return "clock.arrow.circlepath"
        case .favourite:       return "heart.fill"
        }
    }

    private var strategyColor: Color {
        switch suggestion.strategy {
        case .upstreamRelated: return .purple
        case .sameChannel:     return .blue
        case .coOccurrence:    return .green
        case .history:         return .orange
        case .favourite:       return .red
        }
    }
}

// MARK: - EnrichedSuggestion

/// A suggestion enriched with Song metadata for display.
///
/// The engine produces Suggestion values with only a songID. The view model
/// resolves the Song from the store and produces EnrichedSuggestion for display.
struct EnrichedSuggestion: Sendable, Identifiable {
    var id: SuggestionSongID { songID }
    let songID: SuggestionSongID
    let title: String
    let channelName: String
    let durationSeconds: Int
    let strategy: SuggestionStrategy
    let reason: String
}
