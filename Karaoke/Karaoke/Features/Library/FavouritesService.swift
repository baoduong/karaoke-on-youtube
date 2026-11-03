// T115 — FavouritesService.
//
// Add/remove favourites, pinning the Song against unreferenced cleanup.
//
// Favouriting a Song inserts a Favourite record whose `songID` foreign key
// keeps the Song alive in the store (data-model invariant 2: a Song is
// retained if and only if it is referenced by a Favourite, QueueEntry, or
// SavedSong). Removing the last reference allows StoreReconciler to clean
// up the Song on next launch.
//
// FR-027: favourites survive app restart.

import Foundation
import SwiftData
import os.log

// MARK: - FavouritesService

/// Manages the singer's favourites list.
///
/// All mutations run on `@MainActor` so SwiftUI views observe changes without
/// explicit dispatching.
@MainActor
@Observable
final class FavouritesService {

    // MARK: - Observable state

    /// All favourites, newest first (data-model.md Favourite: "Default sort
    /// order is newest first").
    private(set) var favourites: [Favourite] = []

    // MARK: - Private

    private let context: ModelContext
    private static let log = Logger(subsystem: "com.karaoke.personal", category: "favourites")

    // MARK: - Init

    init(context: ModelContext) {
        self.context = context
        loadFavourites()
    }

    // MARK: - Queries

    /// Returns true when the song with `songID` is in the favourites list.
    func isFavourite(songID: String) -> Bool {
        favourites.contains { $0.songID == songID }
    }

    // MARK: - Mutations (T115)

    /// Adds `songID` to favourites.
    ///
    /// A Song is favourited at most once (data-model.md Favourite: primary key
    /// is `songID`). If already favourited, this is a no-op.
    ///
    /// Pinning: inserting the Favourite record keeps the Song alive in the
    /// store (data-model invariant 2).
    func add(songID: String) {
        guard !isFavourite(songID: songID) else { return }
        let favourite = Favourite(songID: songID)
        context.insert(favourite)
        save()
        loadFavourites()
    }

    /// Removes the favourite for `songID`.
    ///
    /// If the Song has no other references (no QueueEntry, no SavedSong),
    /// StoreReconciler will remove it on next launch (data-model invariant 2).
    func remove(songID: String) {
        guard let favourite = favourites.first(where: { $0.songID == songID }) else { return }
        context.delete(favourite)
        save()
        loadFavourites()
    }

    /// Toggles the favourite state for `songID`.
    func toggle(songID: String) {
        if isFavourite(songID: songID) {
            remove(songID: songID)
        } else {
            add(songID: songID)
        }
    }

    // MARK: - Private helpers

    /// Loads all Favourite records from the store, newest first.
    private func loadFavourites() {
        let descriptor = FetchDescriptor<Favourite>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        do {
            favourites = try context.fetch(descriptor)
        } catch {
            Self.log.error("favourites: fetch failed — \(error.localizedDescription, privacy: .public)")
            favourites = []
        }
    }

    /// Persists pending changes to the SwiftData store.
    private func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("favourites: save failed — \(error.localizedDescription, privacy: .public)")
        }
    }
}
