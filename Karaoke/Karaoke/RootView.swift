// Phase 4 — RootView wired to the real search and player UI (User Story 1).
//
// Replaces the Phase 1 placeholder. The search screen is the entry point;
// selecting a result opens the player.

import SwiftUI

/// The root view of the karaoke app.
///
/// Wires the search screen to the player screen. The router is configured with
/// DataAPISearchProvider (for search and metadata) and OnDeviceSourceProvider
/// (for rendition resolution and stream addresses), in that order.
struct RootView: View {

    @State private var router = makeRouter()
    @State private var searchViewModel: SearchViewModel
    @State private var session: PlaybackSession
    @State private var showPlayer = false
    @State private var pendingSong: SongMetadata?

    init() {
        let router = Self.makeRouter()
        let pipeline = PlayerPipeline()
        let cache = StreamAddressCache()
        _router = State(initialValue: router)
        _searchViewModel = State(initialValue: SearchViewModel(router: router))
        _session = State(initialValue: PlaybackSession(pipeline: pipeline, router: router, addressCache: cache))
    }

    var body: some View {
        Group {
            if showPlayer, let song = pendingSong {
                playerScreen(song: song)
            } else {
                searchScreen
            }
        }
    }

    // MARK: Search screen

    private var searchScreen: some View {
        SearchView(viewModel: searchViewModel) { song in
            pendingSong = song
            showPlayer = true
            Task {
                await loadAndPlay(song: song)
            }
        }
    }

    // MARK: Player screen

    private func playerScreen(song: SongMetadata) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showPlayer = false
                    session.stop()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Search")
                }
                .padding()
                Spacer()
            }

            if let error = session.lastError {
                PlaybackErrorView(
                    error: error,
                    onRetry: {
                        Task { await loadAndPlay(song: song) }
                    },
                    onDismiss: {
                        showPlayer = false
                        session.stop()
                    }
                )
            } else {
                PlayerView(session: session) {
                    showPlayer = false
                    session.stop()
                }
            }
        }
    }

    // MARK: Load and play

    private func loadAndPlay(song: SongMetadata) async {
        do {
            let renditions = try await router.audioRenditions(for: song.id)
            let selected = try RenditionSelection.select(from: renditions, songID: song.id)
            await session.play(songID: song.id, rendition: selected)
        } catch {
            _ = error
        }
    }

    // MARK: Router factory

    private static func makeRouter() -> SourceProviderRouter {
        SourceProviderRouter(ordered: [
            DataAPISearchProvider(),
            OnDeviceSourceProvider(),
            CompanionSourceProvider(),
        ])
    }
}

#Preview {
    RootView()
}
