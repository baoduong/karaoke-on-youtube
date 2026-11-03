import Foundation
import Observation

/// Asks the companion to build manifests for songs nobody has picked yet.
///
/// Building one runs yt-dlp on the companion and measured about three
/// seconds. Doing that while the current song plays means the next tap lands
/// on a manifest the companion has already built and cached.
///
/// Nothing is stored here: the response body is thrown away, because the
/// cache that matters is the companion's. That also answers how this expires
/// — the set of attempted ids lives in memory and dies with the app.
///
/// Songs are warmed strictly one at a time. Each one spawns a yt-dlp process
/// on the singer's laptop, and several at once would compete with the song
/// currently playing for the same CPU.
@MainActor
@Observable
final class ManifestPrewarmer {

    /// Songs still to warm, counting the one in flight. Zero means idle.
    private(set) var remaining: Int = 0

    private var attempted: Set<String> = []
    private var pending: [URL] = []
    private var isDraining = false

    func warm(_ targets: [(songID: String, manifest: URL)]) {
        for target in targets where !attempted.contains(target.songID) {
            attempted.insert(target.songID)
            pending.append(target.manifest)
        }
        guard !pending.isEmpty else { return }
        remaining = pending.count + (isDraining ? 1 : 0)
        guard !isDraining else { return }
        Task { await drain() }
    }

    private func drain() async {
        isDraining = true
        while !pending.isEmpty {
            let url = pending.removeFirst()
            remaining = pending.count + 1
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            _ = try? await URLSession.shared.data(for: request)
        }
        remaining = 0
        isDraining = false
    }
}
