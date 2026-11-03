import SwiftData
import SwiftUI

/// The app shell.
///
/// Four tabs, because six screens had been built with nothing navigating to
/// them: Settings, Queue, Library, SavedSongs, Suggestions and SourceVideo all
/// compiled and passed their tests while being unreachable. Three user stories
/// were effectively unshipped as a result, which no unit test could have
/// caught — there is nothing to assert about a view nobody can open.
struct RootView: View {

    @State private var router = makeRouter()
    @State private var searchViewModel: SearchViewModel
    @State private var session: PlaybackSession
    @State private var queueService: QueueService
    @State private var favouritesService: FavouritesService
    @State private var settings: PerformanceSettings
    @State private var suggestionsState: SuggestionsState = .idle
    @State private var selectedTab: Int = Self.initialTab
    @State private var lyrics = LyricsViewModel()

    private let modelContext: ModelContext
    private let mediaStore: MediaStore
    private let saveCoordinator: SaveCoordinator
    private let suggestionEngine: BlendedRecommendationEngine
    private let lyricsProvider: LyricsProvider
    private let companion = CompanionSourceProvider()

    @State private var pendingSong: SongMetadata?
    @State private var showPlayer = false

    init() {
        let router = Self.makeRouter()
        let store = MediaStore.shared
        let context = ModelContext(store.container)

        _router = State(initialValue: router)
        _searchViewModel = State(initialValue: SearchViewModel(router: router))
        _session = State(initialValue: PlaybackSession(
            pipeline: PlayerPipeline(),
            router: router,
            addressCache: StreamAddressCache()
        ))
        _queueService = State(initialValue: QueueService(context: context))
        _favouritesService = State(initialValue: FavouritesService(context: context))
        _settings = State(initialValue: Self.loadSettings(context: context))

        modelContext = context
        mediaStore = store
        saveCoordinator = SaveCoordinator(mediaStore: store)
        suggestionEngine = BlendedRecommendationEngine(providers: [
            SameChannelStrategy(modelContext: context),
            CoOccurrenceStrategy(modelContext: context),
            HistoryStrategy(modelContext: context),
            FavouriteStrategy(modelContext: context)
        ])
        lyricsProvider = LRCLIBProvider()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            singTab
                .tag(0)
                .tabItem { Label("Sing", systemImage: "music.mic") }

            QueueView(service: queueService)
                .tag(1)
                .tabItem { Label("Queue", systemImage: "list.number") }

            libraryTab
                .tag(2)
                .tabItem { Label("Library", systemImage: "heart") }

            SettingsView(settings: settings)
                .tag(3)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // Locked to dark rather than following the system. The palette is a
        // fixed set of values, and the room this gets used in is dim; a light
        // appearance switching on mid-party would be worse than no choice at
        // all. Declaring it keeps the behaviour deliberate instead of a side
        // effect of the palette ignoring the system setting.
        .preferredColorScheme(.dark)
        .tint(Theme.Palette.accent)
        .modelContext(modelContext)
        .task {
            queueService.restoreOnLaunch()
            runDemoSearchIfRequested()
            await startDemoSongIfRequested()
        }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            tickLyrics()
        }
    }

    // MARK: Sing

    @ViewBuilder
    private var singTab: some View {
        if showPlayer, let song = pendingSong {
            playerScreen(song: song)
        } else {
            SearchView(viewModel: searchViewModel) { song in
                pendingSong = song
                showPlayer = true
                Task { await loadAndPlay(song: song) }
            }
        }
    }

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
                    onRetry: { Task { await loadAndPlay(song: song) } },
                    onDismiss: {
                        showPlayer = false
                        session.stop()
                    }
                )
            } else {
                ScrollView {
                    PlayerView(session: session, song: song) {
                        showPlayer = false
                        session.stop()
                    }

                    LyricsView(viewModel: lyrics, fontScale: settings.lyricsFontScale)
                        .padding(.top, 12)

                    SuggestionsView(
                        state: suggestionsState,
                        onAddToQueue: { songID in
                            queueService.enqueue(songID: songID)
                        },
                        onPlayNow: { songID in
                            Task { await playByID(songID) }
                        }
                    )
                    .padding(.top, 12)
                }
            }
        }
    }

    // MARK: Library

    private var libraryTab: some View {
        NavigationStack {
            List {
                NavigationLink("Favourites") {
                    LibraryView(favouritesService: favouritesService, queueService: queueService)
                }
                NavigationLink("Saved for offline") {
                    SavedSongsView(mediaStore: mediaStore, coordinator: saveCoordinator)
                }
            }
            .navigationTitle("Library")
        }
    }

    // MARK: Playback

    private func loadAndPlay(song: SongMetadata) async {
        do {
            let renditions = try await router.audioRenditions(for: song.id)
            let selected = try RenditionSelection.select(from: renditions, songID: song.id)
            // Video carries the words on most karaoke uploads, and the HLS
            // audio variant is the same itag as the audio-only path, so this
            // is free (FR-021). No companion configured means no video.
            if let manifest = companion.hlsManifestURL(for: song.id) {
                await session.playHLS(songID: song.id, manifestURL: manifest, rendition: selected)
            } else {
                await session.play(songID: song.id, rendition: selected)
            }
            await refreshSuggestions(for: song.id)
            await loadLyrics(for: song)
        } catch {
            DiagnosticLog.recordMechanismError(error, songID: song.id, providerID: router.identifier)
        }
    }

    private func playByID(_ songID: String) async {
        do {
            let metadata = try await router.metadata(for: SourceReference(songID: songID))
            pendingSong = metadata
            await loadAndPlay(song: metadata)
        } catch {
            DiagnosticLog.recordMechanismError(error, songID: songID, providerID: router.identifier)
        }
    }

    /// Suggestions are regenerated per song and never cached: the exclusion
    /// set changes every few minutes, so a cached list is a stale one (T101).
    private func refreshSuggestions(for songID: String) async {
        suggestionsState = .loading
        let results = await suggestionEngine.suggestions(
            for: songID,
            excluding: session.performedSongIDs,
            limit: 8
        )
        suggestionsState = results.isEmpty ? .coldStart : .loaded(results)
    }

    /// Lyrics never block playback: they are fetched after audio has started
    /// and their absence changes nothing (FR-025d's sibling rule for US3).
    private func loadLyrics(for song: SongMetadata) async {
        lyrics.setTrack(nil)
        let query = LyricsQuery(
            title: song.title,
            artist: song.channelName,
            durationSeconds: song.durationSeconds
        )
        let track = try? await lyricsProvider.lyrics(for: query)
        lyrics.setTrack(track)
    }

    /// The audio clock is the only clock: the view asks the session for its
    /// position rather than keeping one, which is how lyric drift is avoided.
    private func tickLyrics() {
        lyrics.update(
            positionSeconds: session.positionSeconds,
            outputLatencyMs: session.outputLatencyMs,
            globalOffsetMs: lyrics.track?.globalOffsetMs ?? 0,
            manualLyricsOffsetMs: settings.manualLyricsOffsetMs
        )
    }

    /// DEBUG-only initial tab, set with `-uiTab <0-3>` at launch. The
    /// simulator offers no way to tap a tab bar from the command line, so
    /// screenshotting each tab during UI work needs this.
    private static var initialTab: Int {
        #if DEBUG
        let requested = UserDefaults.standard.integer(forKey: "uiTab")
        return (0...3).contains(requested) ? requested : 0
        #else
        return 0
        #endif
    }

    /// DEBUG-only: run a search given with `-uiDemoSearch <query>`, so the
    /// result rows can be inspected with real Vietnamese titles rather than
    /// imagined ones.
    private func runDemoSearchIfRequested() {
        #if DEBUG
        guard let query = UserDefaults.standard.string(forKey: "uiDemoSearch"), !query.isEmpty else { return }
        searchViewModel.queryText = query
        searchViewModel.resolveDirectReference()
        #endif
    }

    /// DEBUG-only: auto-play a song given with `-uiDemoSong <videoID>`.
    /// The simulator cannot be typed into from the command line, so verifying
    /// the player's appearance needs a way in that is not the keyboard.
    private func startDemoSongIfRequested() async {
        #if DEBUG
        guard let id = UserDefaults.standard.string(forKey: "uiDemoSong"), !id.isEmpty else { return }
        do {
            let metadata = try await router.metadata(for: SourceReference(songID: id))
            pendingSong = metadata
            showPlayer = true
            await loadAndPlay(song: metadata)
        } catch {
            DiagnosticLog.recordMechanismError(error, songID: id, providerID: router.identifier)
        }
        #endif
    }

    // MARK: Factories

    private static func loadSettings(context: ModelContext) -> PerformanceSettings {
        let existing = try? context.fetch(FetchDescriptor<PerformanceSettings>())
        if let found = existing?.first { return found }
        let created = PerformanceSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    /// Provider order, which is also the search policy.
    ///
    /// The companion goes first because it has no key and no daily quota,
    /// while the Data API allows 100 searches per day — a single party's
    /// worth. The Data API stays as the fallback for when the companion is
    /// not running, and the on-device resolver sits between them because it
    /// resolves streams but cannot search at all.
    private static func makeRouter() -> SourceProviderRouter {
        SourceProviderRouter(ordered: [
            CompanionSourceProvider(),
            OnDeviceSourceProvider(),
            DataAPISearchProvider()
        ])
    }
}

#Preview {
    RootView()
}
