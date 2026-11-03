import Foundation

// MARK: - StreamAddressCache

/// Caches resolved StreamAddresses and refreshes them before expiry.
///
/// Rules (data-model.md StreamAddress, contracts/source-provider.md):
/// - Refresh BEFORE expiry (at expiresAt minus safetyMargin), never after failure.
///   This is what makes FR-007 produce no audible gap.
/// - Never persist an address (data-model invariant 4).
/// - Never log the url in full (data-model invariant 4).
actor StreamAddressCache {

    private struct CacheKey: Hashable {
        let songID: SongID
        let itag: Int
    }

    private var cache: [CacheKey: StreamAddress] = [:]

    // MARK: Public API

    /// Return a valid StreamAddress, refreshing if stale.
    ///
    /// - Parameters:
    ///   - songID: The song identifier.
    ///   - itag: The rendition itag.
    ///   - provider: The provider to use for re-resolution.
    /// - Returns: A non-stale StreamAddress.
    func address(
        for songID: SongID,
        itag: Int,
        provider: any SourceProvider
    ) async throws(SourceError) -> StreamAddress {
        let key = CacheKey(songID: songID, itag: itag)

        if let cached = cache[key], !cached.isStale {
            return cached
        }

        let fresh = try await provider.streamAddress(for: songID, itag: itag)
        cache[key] = fresh
        return fresh
    }

    /// Invalidate the cached address for a song/itag pair.
    func invalidate(songID: SongID, itag: Int) {
        cache.removeValue(forKey: CacheKey(songID: songID, itag: itag))
    }

    /// Invalidate all cached addresses for a song.
    func invalidateAll(for songID: SongID) {
        cache = cache.filter { $0.key.songID != songID }
    }

    /// Remove all stale entries. Call periodically to avoid unbounded growth.
    func evictStale() {
        cache = cache.filter { !$0.value.isExpired }
    }
}
