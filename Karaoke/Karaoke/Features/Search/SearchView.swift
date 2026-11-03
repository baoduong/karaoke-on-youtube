import SwiftUI

/// The search screen.
///
/// Search is submit-driven — the singer presses Search or the keyboard return
/// key. Keystroke-driven search is forbidden because the Data API fallback
/// allows only 100 calls per day (research.md R2).
struct SearchView: View {

    @Bindable var viewModel: SearchViewModel
    var onSelect: (SongMetadata) -> Void

    @FocusState private var fieldFocused: Bool

    private var trimmedQuery: String {
        viewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    content
                }
            }
            .navigationTitle("Sing")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.textTertiary)

                TextField(
                    "",
                    text: $viewModel.queryText,
                    prompt: Text("Song title or YouTube link")
                        .foregroundStyle(Theme.Palette.textTertiary)
                )
                .focused($fieldFocused)
                .foregroundStyle(Theme.Palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit(submit)

                if !trimmedQuery.isEmpty {
                    Button {
                        viewModel.queryText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: Theme.Hit.control)
            .card(Theme.Palette.surface)

            Button(action: submit) {
                Text("Search")
                    .font(.headline)
                    .padding(.horizontal, Theme.Space.lg)
                    .frame(height: Theme.Hit.control)
            }
            .background(
                trimmedQuery.isEmpty ? Theme.Palette.surface : Theme.Palette.accent,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .foregroundStyle(trimmedQuery.isEmpty ? Theme.Palette.textTertiary : .black)
            .disabled(trimmedQuery.isEmpty)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
    }

    private func submit() {
        fieldFocused = false
        viewModel.resolveDirectReference()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingState
        } else if let error = viewModel.lastError {
            errorState(error)
        } else if viewModel.results.isEmpty {
            // Before any search and after a fruitless one are different
            // situations and should not look identical.
            if trimmedQuery.isEmpty {
                EmptyStateView(
                    icon: "music.mic",
                    title: "What are we singing?",
                    message: "Search for a song, or paste a YouTube link."
                )
                .frame(maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No results",
                    message: "Try a different wording, or paste the link directly."
                )
                .frame(maxHeight: .infinity)
            }
        } else {
            resultsList
        }
    }

    private var loadingState: some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView()
                .tint(Theme.Palette.accent)
            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.sm) {
                ForEach(viewModel.results, id: \.id) { song in
                    Button {
                        viewModel.select(song)
                        onSelect(song)
                    } label: {
                        SongResultRow(song: song)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xl)
        }
    }

    /// Content-side and mechanism-side failures are deliberately different
    /// shapes: one means pick another song, the other means the app needs
    /// fixing (FR-008).
    private func errorState(_ error: SearchError) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: error.isMechanismSide ? "wrench.and.screwdriver.fill" : "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(error.isMechanismSide ? Theme.Palette.mechanismIssue : Theme.Palette.contentIssue)

            Text(error.isMechanismSide ? "Search isn't working" : "Nothing found")
                .font(.headline)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: submit)
                .font(.headline)
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: Theme.Hit.minimum)
                .card(Theme.Palette.surfaceRaised)
                .foregroundStyle(Theme.Palette.accent)
                .padding(.top, Theme.Space.sm)
        }
        .frame(maxWidth: 360)
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SongResultRow

/// One search result: thumbnail, title, channel, duration (FR-001).
///
/// The title gets two lines because Vietnamese karaoke titles are long and
/// carry the part that matters — the key, as in "Tone Nam" — at the end.
/// Truncating to one line would hide exactly the information being scanned for.
struct SongResultRow: View {

    let song: SongMetadata

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            thumbnail

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(song.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Theme.Space.sm) {
                    Text(song.channelName)
                        .lineLimit(1)
                    Text("·")
                    Text(song.durationSeconds.asDurationLabel)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var thumbnail: some View {
        AsyncImage(url: song.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    Theme.Palette.surfaceRaised
                    Image(systemName: "music.note")
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }
}
