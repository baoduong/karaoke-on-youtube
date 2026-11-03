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
import SwiftData

// MARK: - SuggestionsView

/// Displays suggested next songs for the currently playing song.
///
/// Shows title, channel, duration, and the singer-facing reason badge per
/// suggestion (FR-025a, FR-025f). Provides add-to-queue and play-now actions
/// (FR-025e).
struct SuggestionsView: View {

    let state: SuggestionsState
    var onAddToQueue: ((SuggestionSongID) -> Void)?
    var onPlayNow: ((SuggestionSongID) -> Void)?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()

            case .loading:
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    SectionHeading(title: "Up Next")
                    loadingView
                }
                .padding(.horizontal, Theme.Space.lg)

            case .coldStart:
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    SectionHeading(title: "Up Next")
                    coldStartView
                }
                .padding(.horizontal, Theme.Space.lg)

            case .loaded(let suggestions):
                if suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        SectionHeading(title: "Up Next")
                        coldStartView
                    }
                    .padding(.horizontal, Theme.Space.lg)
                } else {
                    suggestionsList(suggestions)
                }
            }
        }
    }

    // MARK: Loading state

    private var loadingView: some View {
        HStack(spacing: Theme.Space.md) {
            ProgressView()
                .tint(Theme.Palette.accent)
            Text("Finding suggestions…")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
        }
        .padding(Theme.Space.lg)
        .card(Theme.Palette.surface)
    }

    // MARK: Cold-start state (T100)

    /// Explicit cold-start state — not a loading state.
    ///
    /// With no history and no upstream data the app says so plainly inside a
    /// deliberate card surface rather than rendering an empty space that looks
    /// like it is still loading (recommendation-provider.md Cold start).
    private var coldStartView: some View {
        EmptyStateView(
            icon: "music.note.list",
            title: "No suggestions yet",
            message: "Sing a few songs and suggestions will appear here."
        )
        .frame(maxWidth: .infinity)
        .card(Theme.Palette.surface)
    }

    // MARK: Suggestions list

    private func suggestionsList(_ suggestions: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeading(
                title: "Up Next",
                trailing: "\(suggestions.count)"
            )

            LazyVStack(spacing: Theme.Space.sm) {
                ForEach(suggestions, id: \.songID) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        context: modelContext,
                        onAddToQueue: { onAddToQueue?(suggestion.songID) },
                        onPlayNow: { onPlayNow?(suggestion.songID) }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }
}

// MARK: - SuggestionRow

/// One row in the suggestions list.
///
/// Resolves `Song` metadata from `ModelContext` so the singer sees the full
/// Vietnamese title (2 lines), channel name, duration, and a compact reason
/// badge explaining why the strategy recommended it (FR-025a, FR-025e, FR-025f).
private struct SuggestionRow: View {

    let suggestion: Suggestion
    let context: ModelContext
    var onAddToQueue: (() -> Void)?
    var onPlayNow: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                reasonBadge

                Text(songTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Theme.Space.sm) {
                    if !channelName.isEmpty {
                        Text(channelName)
                            .lineLimit(1)
                    }
                    if let seconds = durationSeconds, seconds > 0 {
                        if !channelName.isEmpty {
                            Text("·")
                        }
                        Text(seconds.asDurationLabel)
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 0)

            // Actions (FR-025e) — sized for one-handed operation with a microphone.
            HStack(spacing: Theme.Space.sm) {
                Button {
                    onAddToQueue?()
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: Theme.Hit.minimum, height: Theme.Hit.minimum)
                        .background(Theme.Palette.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to queue")

                Button {
                    onPlayNow?()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(width: Theme.Hit.minimum, height: Theme.Hit.minimum)
                        .background(Theme.Palette.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play now")
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Theme.Palette.surface)
    }

    // MARK: - Reason Badge (FR-025f)

    private var reasonBadge: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: strategyIcon)
                .font(.caption2.weight(.semibold))
            Text(suggestion.reason)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Palette.accent)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 3)
        .background(Theme.Palette.accent.opacity(0.14), in: Capsule())
    }

    private var strategyIcon: String {
        switch suggestion.strategy {
        case .upstreamRelated: return "sparkles"
        case .sameChannel:     return "tv"
        case .coOccurrence:    return "person.2.fill"
        case .history:         return "clock.arrow.circlepath"
        case .favourite:       return "heart.fill"
        }
    }

    // MARK: - Song Metadata Lookup

    private var song: Song? {
        let targetID = suggestion.songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private var songTitle: String {
        song?.title ?? suggestion.songID
    }

    private var channelName: String {
        song?.channelName ?? ""
    }

    private var durationSeconds: Int? {
        song?.durationSeconds
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
