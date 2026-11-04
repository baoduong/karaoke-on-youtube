// T117 — LibraryView.
//
// Lists favourites newest first (data-model.md Favourite: "Default sort order
// is newest first") and provides card-styled navigation rows for Favourites
// and Saved for offline.
//
// FR-027: favourites survive app restart.

import SwiftUI
import SwiftData

// MARK: - LibraryView

/// Displays the library hub ("Favourites" and "Saved for offline" navigation cards
/// with counts) alongside the singer's favourites list, newest first.
///
/// `RootView` hosts `LibraryView` inside a `NavigationLink("Favourites")` on the
/// Library tab without touching `RootView.swift`. Surfacing both collection cards
/// ("Favourites" and "Saved for offline") at the top of `LibraryView` alongside the
/// favourites list satisfies the card-styled navigation requirement while preserving
/// the existing `(favouritesService:queueService:)` initializer and full favourites
/// management (enqueue, remove, swipe actions).
struct LibraryView: View {

    // MARK: - Dependencies

    @Bindable var favouritesService: FavouritesService
    var queueService: QueueService

    @Environment(\.modelContext) private var context

    @Query(sort: \SavedSong.savedAt, order: .reverse)
    private var savedSongs: [SavedSong]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                List {
                    Section {
                        collectionsSection
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: Theme.Space.xs,
                                leading: Theme.Space.lg,
                                bottom: Theme.Space.md,
                                trailing: Theme.Space.lg
                            ))
                    }

                    Section {
                        if favouritesService.favourites.isEmpty {
                            EmptyStateView(
                                icon: "heart",
                                title: "No favourites yet",
                                message: "Mark songs as favourites to find them here quickly."
                            )
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                            ForEach(favouritesService.favourites, id: \.songID) { favourite in
                                FavouriteRowView(
                                    favourite: favourite,
                                    context: context,
                                    onAddToQueue: { queueService.enqueue(songID: favourite.songID) },
                                    onRemove: { favouritesService.remove(songID: favourite.songID) }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: Theme.Space.xs,
                                    leading: Theme.Space.lg,
                                    bottom: Theme.Space.xs,
                                    trailing: Theme.Space.lg
                                ))
                            }
                            .onDelete { offsets in
                                let items = favouritesService.favourites
                                for index in offsets {
                                    favouritesService.remove(songID: items[index].songID)
                                }
                            }
                        }
                    } header: {
                        SectionHeading(
                            title: "Favourites",
                            trailing: "\(favouritesService.favourites.count)"
                        )
                        .textCase(nil)
                        .padding(.bottom, Theme.Space.xs)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.Palette.background)
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
        }
    }

    // MARK: - Collections Navigation Cards

    private var collectionsSection: some View {
        VStack(spacing: Theme.Space.sm) {
            NavigationLink {
                FavouritesDetailListView(
                    favouritesService: favouritesService,
                    queueService: queueService
                )
            } label: {
                LibraryCollectionRow(
                    icon: "heart.fill",
                    iconColor: Theme.Palette.accent,
                    title: "Favourites",
                    count: favouritesService.favourites.count
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SavedSongsView(
                    mediaStore: MediaStore.shared,
                    coordinator: SaveCoordinator(mediaStore: MediaStore.shared)
                )
            } label: {
                LibraryCollectionRow(
                    icon: "arrow.down.circle.fill",
                    iconColor: Theme.Palette.success,
                    title: "Saved for offline",
                    count: savedSongs.count
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - LibraryCollectionRow

private struct LibraryCollectionRow: View {

    let icon: String
    let iconColor: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer()

            Text("\(count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .background(Theme.Palette.surfaceRaised, in: Capsule())

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(Theme.Space.md)
        .frame(minHeight: Theme.Hit.control)
        .card(Theme.Palette.surface)
    }
}

// MARK: - FavouritesDetailListView

private struct FavouritesDetailListView: View {

    @Bindable var favouritesService: FavouritesService
    var queueService: QueueService

    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            if favouritesService.favourites.isEmpty {
                EmptyStateView(
                    icon: "heart",
                    title: "No favourites yet",
                    message: "Mark songs as favourites to find them here quickly."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(favouritesService.favourites, id: \.songID) { favourite in
                        FavouriteRowView(
                            favourite: favourite,
                            context: context,
                            onAddToQueue: { queueService.enqueue(songID: favourite.songID) },
                            onRemove: { favouritesService.remove(songID: favourite.songID) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: Theme.Space.xs,
                            leading: Theme.Space.lg,
                            bottom: Theme.Space.xs,
                            trailing: Theme.Space.lg
                        ))
                    }
                    .onDelete { offsets in
                        let items = favouritesService.favourites
                        for index in offsets {
                            favouritesService.remove(songID: items[index].songID)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.Palette.background)
            }
        }
        .navigationTitle("Favourites")
        .toolbarBackground(Theme.Palette.background, for: .navigationBar)
    }
}

// MARK: - FavouriteRowView

/// A single row in the favourites list.
///
/// Looks up the Song by `songID` to display title (up to 2 lines for Vietnamese
/// karaoke titles), channel, and duration, with large one-handed action buttons
/// plus swipe actions.
private struct FavouriteRowView: View {

    let favourite: Favourite
    let context: ModelContext
    let onAddToQueue: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "heart.fill")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 32, height: 32)
                .background(Theme.Palette.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(songTitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Theme.Space.sm) {
                    if !songSubtitle.isEmpty {
                        Text(songSubtitle)
                            .lineLimit(1)
                    }
                    if let seconds = song?.durationSeconds {
                        if !songSubtitle.isEmpty {
                            Text("·")
                        }
                        Text(seconds.asDurationLabel)
                            .monospacedDigit()
                    }
                }
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 0)

            Button(action: onAddToQueue) {
                Image(systemName: "text.badge.plus")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: Theme.Hit.minimum, height: Theme.Hit.minimum)
                    .background(Theme.Palette.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Queue")
        }
        .padding(Theme.Space.md)
        .frame(minHeight: Theme.Hit.control)
        .card()
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
            .tint(Theme.Palette.accent)
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
}
