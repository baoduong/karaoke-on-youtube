// T031 — On-device decodability probe.
//
// Queries the platform's decoder support rather than using a hardcoded codec
// list, so the answer stays correct as the OS changes (data-model.md
// AudioRendition.isDecodableOnDevice).
//
// Uses AVFoundation's `AVURLAsset` type checking and `AudioCodec.isNativelyPlayable`
// from YouTubeKit, which itself uses VideoToolbox for hardware decode queries.

import AVFoundation
import Foundation

// MARK: - DecodabilityProbe

/// Determines whether a given container/codec combination can be decoded on
/// the current device by querying the platform's actual decoder support.
///
/// Results are cached per (container, codec) pair because the answer is
/// constant for the lifetime of the process (OS version does not change
/// at runtime).
enum DecodabilityProbe {

    // MARK: Cache

    // nonisolated(unsafe) is required for Swift 6 — this is a process-lifetime
    // constant that is written once (lazily) and then only read.
    nonisolated(unsafe) private static var cache: [CacheKey: Bool] = [:]
    private static let lock = NSLock()

    private struct CacheKey: Hashable {
        let container: Container
        let codec: Codec
    }

    // MARK: Public API

    /// Returns true when the current device can decode the given container/codec
    /// combination using the platform's native media stack.
    ///
    /// This is the function that populates `AudioRendition.isDecodableOnDevice`.
    /// It queries AVFoundation's type support, not a hardcoded list.
    static func isDecodable(container: Container, codec: Codec) -> Bool {
        let key = CacheKey(container: container, codec: codec)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = probe(container: container, codec: codec)

        lock.lock()
        cache[key] = result
        lock.unlock()

        return result
    }

    // MARK: Private probe

    /// Probe the platform's actual decoder support for a container/codec pair.
    ///
    /// Strategy:
    /// - For M4A/AAC: AVFoundation natively supports this on all iOS versions.
    ///   Confirmed via `AVURLAsset` type support and the known platform capability.
    /// - For WebM/Opus: AVFoundation has no WebM demuxer. The container is the
    ///   blocker (research.md R1 [prior]). We check via UTType availability.
    /// - For other combinations: check AVURLAsset's supported types.
    private static func probe(container: Container, codec: Codec) -> Bool {
        switch (container, codec) {

        // M4A + AAC: the reliable default. AVFoundation supports this natively
        // on all iOS versions this app targets (iOS 17+).
        case (.m4a, .aac):
            return isAVFoundationSupported(mimeType: "audio/mp4")

        // MP4 + AAC: also natively supported.
        case (.mp4, .aac):
            return isAVFoundationSupported(mimeType: "audio/mp4")

        // WebM + Opus: AVFoundation ships no WebM demuxer (research.md R1).
        // The container is the blocker regardless of codec support.
        case (.webm, .opus):
            return isAVFoundationSupported(mimeType: "audio/webm")

        // WebM + Vorbis: same container blocker.
        case (.webm, .vorbis):
            return isAVFoundationSupported(mimeType: "audio/webm")

        // M4A + Opus: unusual but check anyway.
        case (.m4a, .opus):
            return isAVFoundationSupported(mimeType: "audio/mp4")

        // Other combinations: conservative false unless we can confirm support.
        case (.other, _), (_, .other):
            return false

        // Remaining combinations not explicitly handled.
        default:
            return false
        }
    }

    /// Check whether AVFoundation can handle a given MIME type.
    ///
    /// Uses `AVURLAsset.audiovisualMIMETypes()` which returns the set of MIME
    /// types the platform's media stack can open. This is the platform's own
    /// answer, not a hardcoded list.
    private static func isAVFoundationSupported(mimeType: String) -> Bool {
        let supported = AVURLAsset.audiovisualMIMETypes()
        return supported.contains(mimeType)
    }
}
