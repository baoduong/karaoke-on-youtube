// T117 — LibraryView.
//
// Lists favourites newest first (data-model.md Favourite: "Default sort order
// is newest first").
//
// FR-027: favourites survive app restart.

import SwiftUI
import SwiftData

// MARK: - LibraryView

/// Displays the singer's favourites, newest first.
///
/// Each row shows title, channel, and duration. A swipe-to-unfavourite action
/// removes the entry. The view is driven by `FavouritesService` which owns the
/// sort order and persistence.
struct LibraryView: View {

    // MARK: - Dependencies

    @Bindable var favouritesService: FavouritesService
    var queueService: QueueService

    @Environment(\.modelContext) private var context

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if favouritesService.favourites.isEmpty {
                    emptyState
                } else {
                    favouritesList
                }
            }
            .navigationTitle("Library")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "No favourites yet",
            systemImage: "heart",
            description: Text("Mark songs as favourites to find them here quickly.")
        )
    }

    private var favouritesList: some View {
        List {
            ForEach(favouritesService.favourites, id: \.songID) { favourite in
                FavouriteRowView(
                    favourite: favourite,
                    context: context,
                    onAddToQueue: { queueService.enqueue(songID: favourite.songID) },
                    onRemove: { favouritesService.remove(songID: favourite.songID) }
                )
            }
            .onDelete { offsets in
                let items = favouritesService.favourites
                for index in offsets {
                    favouritesService.remove(songID: items[index].songID)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - FavouriteRowView

/// A single row in the favourites list.
///
/// Looks up the Song by `songID` to display title, channel, and duration.
private struct FavouriteRowView: View {

    let favourite: Favourite
    let context: ModelContext
    let onAddToQueue: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .imageScale(.medium)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(songTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(songSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let duration = songDuration {
                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "heart.slash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onAddToQueue()
            } label: {
                Label("Add to Queue", systemImage: "plus.circle")
            }
            .tint(.accentColor)
        }
    }

    // MARK: - Song lookup

    private var song: Song? {
        let targetID = favourite.songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private var songTitle: String {
        song?.title ?? favourite.songID
    }

    private var songSubtitle: String {
        song?.channelName ?? ""
    }

    private var songDuration: String? {
        guard let seconds = song?.durationSeconds else { return nil }
        return formatDuration(seconds)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
