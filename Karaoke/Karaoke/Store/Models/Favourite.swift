import Foundation
import SwiftData

// MARK: - Favourite

/// A Song the singer has marked as a favourite (FR-027).
///
/// `songID` is the primary key — a Song is favourited at most once.
/// Favouriting pins the Song against unreferenced cleanup (data-model invariant 2):
/// as long as a Favourite exists, the Song is retained in the store.
///
/// Default sort order is newest first (`addedAt` descending).
@Model
final class Favourite {

    // MARK: Stored properties

    /// Foreign key to Song. Primary key — a Song is favourited at most once.
    @Attribute(.unique) var songID: String

    /// When the singer added this favourite. Used for default sort (newest first).
    var addedAt: Date

    // MARK: Init

    init(songID: String, addedAt: Date = Date()) {
        self.songID = songID
        self.addedAt = addedAt
    }
}
