// T030 — Pure rendition ranking function.
//
// Implements data-model.md's Selection Rule exactly. This is a pure function
// so SC-004 can be verified by comparing the function's choice against the
// full set offline.
//
// Selection Rule (FR-004, FR-005):
//   1. Discard every rendition where `isDecodableOnDevice` is false.
//      If the set is now empty, fail with `noAudioRenditions` (distinct from
//      `notFound` — the video exists but has no usable audio).
//   2. Rank the remainder by `averageBitrateBps` descending.
//   3. Break ties by codec preference order from research.md R1.
//   4. Break remaining ties by `channelCount` descending.
//   5. Break remaining ties by `itag` ascending for determinism.
//   6. Select the first.

import Foundation

// MARK: - Codec preference order

/// Codec preference order for tie-breaking, from research.md R1.
///
/// AAC (M4A) is the reliable default on iOS because AVFoundation ships no
/// WebM demuxer — Opus-in-WebM is unplayable without remuxing. If Spike S1
/// proves Opus is decodable, this order should be updated.
///
/// Lower index = higher preference.
private let codecPreferenceOrder: [Codec] = [
    .aac,    // itag 140: AAC-LC ~128 kbps M4A — the reliable default (R1)
    .opus,   // itag 251: Opus ~160 kbps WebM — better if decodable (S1 pending)
    .vorbis, // legacy
    // .other is handled by falling to the end
]

private func codecRank(_ codec: Codec) -> Int {
    if let idx = codecPreferenceOrder.firstIndex(of: codec) {
        return idx
    }
    return codecPreferenceOrder.count // unknown codecs rank last
}

// MARK: - RenditionSelection

/// Pure rendition ranking. Same input → same output.
///
/// This is a free function (not a method on a type) so it is trivially
/// testable without any provider or network dependency.
enum RenditionSelection {

    /// Select the best rendition from a set, following the Selection Rule.
    ///
    /// - Parameter renditions: The full set returned by `audioRenditions(for:)`.
    ///   Must not be pre-filtered by the provider.
    /// - Parameter songID: Used only for error attribution.
    /// - Returns: The selected rendition.
    /// - Throws: `SourceError.noAudioRenditions` when every rendition is
    ///   undecodable on this device. This is distinct from `notFound` — the
    ///   video exists but has no usable audio format.
    static func select(
        from renditions: [AudioRendition],
        songID: SongID
    ) throws(SourceError) -> AudioRendition {
        // Step 1: Discard undecodable renditions.
        let decodable = renditions.filter { $0.isDecodableOnDevice }

        guard !decodable.isEmpty else {
            // The video exists but no rendition can be decoded on this device.
            // This is `noAudioRenditions`, NOT `notFound`.
            throw SourceError.noAudioRenditions(songID)
        }

        // Steps 2–5: Sort by the Selection Rule.
        let ranked = decodable.sorted { lhs, rhs in
            // Step 2: Higher bitrate first.
            let lBitrate = lhs.averageBitrateBps ?? 0
            let rBitrate = rhs.averageBitrateBps ?? 0
            if lBitrate != rBitrate { return lBitrate > rBitrate }

            // Step 3: Codec preference (lower rank index = better).
            let lCodecRank = codecRank(lhs.codec)
            let rCodecRank = codecRank(rhs.codec)
            if lCodecRank != rCodecRank { return lCodecRank < rCodecRank }

            // Step 4: More channels first.
            let lChannels = lhs.channelCount ?? 0
            let rChannels = rhs.channelCount ?? 0
            if lChannels != rChannels { return lChannels > rChannels }

            // Step 5: Lower itag first for determinism.
            return lhs.itag < rhs.itag
        }

        // Step 6: Select the first.
        // ranked is non-empty (guarded above).
        return ranked[0]
    }

    /// Rank all decodable renditions without selecting one.
    ///
    /// Returns the full ranked list so callers can inspect the ordering.
    /// Returns an empty array when all renditions are undecodable.
    static func rank(renditions: [AudioRendition]) -> [AudioRendition] {
        let decodable = renditions.filter { $0.isDecodableOnDevice }
        return decodable.sorted { lhs, rhs in
            let lBitrate = lhs.averageBitrateBps ?? 0
            let rBitrate = rhs.averageBitrateBps ?? 0
            if lBitrate != rBitrate { return lBitrate > rBitrate }

            let lCodecRank = codecRank(lhs.codec)
            let rCodecRank = codecRank(rhs.codec)
            if lCodecRank != rCodecRank { return lCodecRank < rCodecRank }

            let lChannels = lhs.channelCount ?? 0
            let rChannels = rhs.channelCount ?? 0
            if lChannels != rChannels { return lChannels > rChannels }

            return lhs.itag < rhs.itag
        }
    }

    /// Validate that a rendition set has no duplicate itags.
    ///
    /// A duplicate itag indicates a parse fault and must fail resolution rather
    /// than silently picking one (data-model.md AudioRendition Validation).
    ///
    /// - Returns: The first duplicate itag, or nil if all are unique.
    static func firstDuplicateItag(in renditions: [AudioRendition]) -> Int? {
        var seen = Set<Int>()
        for r in renditions {
            if !seen.insert(r.itag).inserted {
                return r.itag
            }
        }
        return nil
    }
}
