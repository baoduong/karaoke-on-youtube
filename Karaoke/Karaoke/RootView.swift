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
    @State private var showQualityDetail = false
    @State private var selectedTab: Int = Self.initialTab

    private let modelContext: ModelContext
    private let mediaStore: MediaStore
    private let saveCoordinator: SaveCoordinator
    private let suggestionEngine: BlendedRecommendationEngine
    private let companion = CompanionSourceProvider()

    @State private var pendingSong: SongMetadata?
    @State private var showPlayer = false

    /// True from the moment a song is tapped until it is playing or has failed.
    ///
    /// Drives the blocking overlay, and is also the re-entrancy guard in
    /// `startSong`. Both are needed: the overlay stops the taps a person
    /// makes after it appears, the guard stops the ones already in flight
    /// before SwiftUI has drawn a frame.
    @State private var isStartingSong = false

    /// The in-flight start, kept so the overlay's Cancel can stop it.
    @State private var startTask: Task<Void, Never>?
    @State private var prewarmer = ManifestPrewarmer()

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
            UpstreamRelatedStrategy(modelContext: context),
            SameChannelStrategy(modelContext: context),
            CoOccurrenceStrategy(modelContext: context),
            HistoryStrategy(modelContext: context),
            FavouriteStrategy(modelContext: context)
        ])
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            singTab
                .tag(0)
                .tabItem { Label("Sing", systemImage: "music.mic") }

            QueueView(service: queueService) { entry in
                start(id: entry.songID, entryID: entry.id)
            }
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
        .overlay(alignment: .bottomTrailing) {
            PrewarmBadge(remaining: prewarmer.remaining)
                .padding(.trailing, Theme.Space.lg)
                .padding(.bottom, 96)
        }
        .overlay { if isStartingSong { startingOverlay } }
        .onChange(of: session.state) { _, state in
            if state == .finished { queueService.currentPlayedOut() }
        }
        .modelContext(modelContext)
        .task {
            queueService.restoreOnLaunch()
            runDemoSearchIfRequested()
            startDemoSongIfRequested()
        }
    }

    // MARK: Starting overlay

    /// Covers everything, tab bar included, while a song is being started.
    ///
    /// Resolving takes two network round trips. Without a cover the screen
    /// looks idle for that whole stretch, and the singer taps the next song,
    /// then another — each tap landing on a different row than the one being
    /// loaded. Swallowing the taps is the point; the spinner only explains
    /// why nothing is responding.
    private var startingOverlay: some View {
        ZStack {
            Color.black.opacity(0.62)

            VStack(spacing: Theme.Space.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Palette.accent)
                Text("Starting song…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.textPrimary)

                // Resolving a song is measured in tens of seconds, so a cover
                // with no way out can strand the singer mid-party.
                Button("Cancel", role: .cancel, action: cancelStart)
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.accent)
                    .padding(.top, Theme.Space.xs)
            }
            .padding(Theme.Space.xl)
            .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(
                cornerRadius: Theme.Radius.lg,
                style: .continuous
            ))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Starting song")
    }

    // MARK: Sing

    @ViewBuilder
    private var singTab: some View {
        if showPlayer {
            if let song = pendingSong {
                playerScreen(song: song)
            } else {
                startingScreen
            }
        } else {
            SearchView(viewModel: searchViewModel) { song in
                start(metadata: song)
            }
        }
    }

    /// Covers the gap between stopping the old song and having metadata for
    /// the new one. Dropping back to search there reads as a cancelled tap.
    private var startingScreen: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlayerVideoStage(
                    player: nil,
                    isLoaded: false,
                    route: session.outputRoute,
                    isStarting: true,
                    onShowQualityDetail: { }
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.background)
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
        }
    }

    /// Wrapped in a NavigationStack with a real toolbar rather than a
    /// hand-rolled header row. The hand-rolled version sat outside any
    /// navigation container, so the safe area was measured against the wrong
    /// thing and left roughly 280pt of dead black above the controls.
    private func playerScreen(song: SongMetadata) -> some View {
        NavigationStack {
            playerBody(song: song)
                .background(Theme.Palette.background)
                .sheet(isPresented: $showQualityDetail) {
                    QualityDetailView(
                        rendition: session.selectedRendition,
                        outputRoute: session.outputRoute
                    )
                }
                .navigationTitle("Now Playing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.Palette.background, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showPlayer = false
                            session.stop()
                        } label: {
                            Label("Search", systemImage: "chevron.left")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func playerBody(song: SongMetadata) -> some View {
        VStack(spacing: 0) {
            // Outside the scroll view on purpose: the words are in the
            // picture on most karaoke uploads, so scrolling the video away
            // would remove what the singer is reading.
            PlayerVideoStage(
                player: session.videoPlayer,
                isLoaded: session.songID != nil,
                route: session.outputRoute,
                onShowQualityDetail: { showQualityDetail = true }
            )

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

                    SuggestionsView(
                        state: suggestionsState,
                        onAddToQueue: { songID in
                            queueService.enqueue(songID: songID)
                        },
                        onPlayNow: { songID in
                            start(id: songID)
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

    /// Gets sound out of the speaker as soon as possible, then catches up.
    ///
    /// Video carries the words on most karaoke uploads, so the HLS stream is
    /// the preferred path (FR-021). It needs no rendition, which is what makes
    /// it fast: resolving one costs about 23 s against roughly 3 s for the
    /// manifest. Only the audio-only fallback genuinely needs an itag.
    private func loadAndPlay(song: SongMetadata) async {
        if let manifest = companion.hlsManifestURL(for: song.id),
           await session.playHLS(songID: song.id, manifestURL: manifest) {
            catchUpAfterStart(songID: song.id)
            return
        }
        await playAudioOnly(song: song)
    }

    /// No companion, or the manifest would not open. This path has to resolve
    /// a rendition because the itag is what builds the stream address.
    private func playAudioOnly(song: SongMetadata) async {
        do {
            let renditions = try await router.audioRenditions(for: song.id)
            let selected = try RenditionSelection.select(from: renditions, songID: song.id)
            await session.play(songID: song.id, rendition: selected)
            catchUpAfterStart(songID: song.id)
        } catch {
            DiagnosticLog.recordMechanismError(error, songID: song.id, providerID: router.identifier)
        }
    }

    /// Work that costs a network round trip and that nobody needs in order to
    /// sing. Started, never awaited: awaiting it held the blocking overlay up
    /// long after the music had started.
    private func catchUpAfterStart(songID: String) {
        Task { await refreshSuggestions(for: songID) }
        Task { await describeAudio(for: songID) }
        prewarmUpcoming()
    }

    /// Builds manifests ahead of the singer for the songs most likely to be
    /// picked next: the top of the queue, then the first suggestions.
    private func prewarmUpcoming(suggestions: [Suggestion] = []) {
        let ids = queueService.waiting.prefix(2).map(\.songID)
            + suggestions.prefix(2).map(\.songID)
        let targets = ids.compactMap { id -> (songID: String, manifest: URL)? in
            guard let url = companion.hlsManifestURL(for: id) else { return nil }
            return (songID: id, manifest: url)
        }
        guard !targets.isEmpty else { return }
        prewarmer.warm(targets)
    }

    /// Fills in the quality sheet behind the ⓘ button after the fact.
    private func describeAudio(for songID: String) async {
        guard let renditions = try? await router.audioRenditions(for: songID),
              let selected = try? RenditionSelection.select(from: renditions, songID: songID)
        else { return }
        session.describe(rendition: selected, forSongID: songID)
    }

    /// Stops whatever is playing and moves the UI to the player, all before
    /// the first `await`.
    ///
    /// The ordering is the fix. Resolution costs two network round trips, and
    /// with the stop placed after them the previous song kept singing for that
    /// whole stretch while the singer waited on the one they had just tapped.
    ///
    /// Returns false when a start is already in flight.
    private func beginStart() -> Bool {
        guard !isStartingSong else { return false }
        isStartingSong = true
        session.stop()
        pendingSong = nil
        suggestionsState = .idle
        showPlayer = true
        selectedTab = 0
        return true
    }

    /// Start a song known only by id — a suggestion or a queue row.
    private func start(id songID: String, entryID: UUID? = nil) {
        guard beginStart() else { return }
        queueService.setCurrent(entryID: entryID, songID: songID)
        startTask = Task { await resolveAndPlay(id: songID) }
    }

    /// Kept a plain method rather than inlined into the `Task` above: inside
    /// a task closure Swift drops the typed-throws inference, and `metadata`
    /// throws `SourceError`, which `DiagnosticLog` requires.
    private func resolveAndPlay(id songID: String) async {
        defer { isStartingSong = false }

        if let known = storedMetadata(for: songID) {
            pendingSong = known
            await loadAndPlay(song: known)
            return
        }

        do {
            let metadata = try await router.metadata(for: SourceReference(songID: songID))
            guard !Task.isCancelled else { return }
            pendingSong = metadata
            await loadAndPlay(song: metadata)
        } catch {
            DiagnosticLog.recordMechanismError(error, songID: songID, providerID: router.identifier)
            showPlayer = false
        }
    }

    /// Start a song whose metadata is already in hand — a search result.
    private func start(metadata: SongMetadata) {
        guard beginStart() else { return }
        queueService.setCurrent(songID: metadata.id)
        pendingSong = metadata
        startTask = Task {
            defer { isStartingSong = false }
            await loadAndPlay(song: metadata)
        }
    }

    /// Title, channel and duration already held locally for this song.
    ///
    /// Search persists every result it shows, and the related-video strategy
    /// persists its candidates, so by the time a song is tappable the store
    /// already knows everything `SongMetadata` carries. Asking upstream again
    /// measured about three seconds of dead time per start.
    private func storedMetadata(for songID: String) -> SongMetadata? {
        let targetID = songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let song = try? modelContext.fetch(descriptor).first else { return nil }
        return SongMetadata(
            id: song.id,
            title: song.title,
            channelName: song.channelName,
            durationSeconds: song.durationSeconds,
            thumbnailURL: song.thumbnailURL
        )
    }

    /// Abandon the start in flight and return to search.
    private func cancelStart() {
        startTask?.cancel()
        startTask = nil
        isStartingSong = false
        queueService.setCurrent(songID: nil)
        session.stop()
        pendingSong = nil
        suggestionsState = .idle
        showPlayer = false
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
        guard session.songID == songID else { return }
        suggestionsState = results.isEmpty ? .coldStart : .loaded(results)
        prewarmUpcoming(suggestions: results)
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
    /// result rows can be inspected with real Vietnamese titles.
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
    private func startDemoSongIfRequested() {
        #if DEBUG
        guard let id = UserDefaults.standard.string(forKey: "uiDemoSong"), !id.isEmpty else { return }
        start(id: id)
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

// MARK: - PrewarmBadge

/// A quiet note, bottom right, that the next songs are being made ready.
///
/// Deliberately not in the way: it sits above the tab bar and takes no taps,
/// because it reports background work the singer never asked for and must
/// never have to dismiss.
private struct PrewarmBadge: View {

    let remaining: Int

    /// Held briefly after the count reaches zero so the finish is visible.
    /// Without it the badge would simply vanish, which reads the same as the
    /// work having been abandoned.
    @State private var showReady = false

    var body: some View {
        Group {
            if remaining > 0 {
                content {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Palette.accent)
                    Text("Caching \(remaining)")
                }
            } else if showReady {
                content {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.success)
                    Text("Ready")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: remaining)
        .animation(.easeInOut(duration: 0.2), value: showReady)
        .allowsHitTesting(false)
        .onChange(of: remaining) { previous, current in
            guard previous > 0, current == 0 else { return }
            showReady = true
        }
        .task(id: showReady) {
            guard showReady else { return }
            try? await Task.sleep(for: .seconds(2.5))
            showReady = false
        }
    }

    private func content<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        HStack(spacing: Theme.Space.xs) {
            inner()
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

#Preview {
    RootView()
}
