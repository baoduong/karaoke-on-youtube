// T057 — SearchView.
//
// Displays search results showing title, channel, and duration per result (FR-001).
// Search is submit-driven — the singer presses Search or the keyboard return key.
// Never keystroke-driven (T053).
//
// Satisfies: FR-001, FR-002

import SwiftUI

// MARK: - SearchView

/// The search screen. Shows a search field and a list of results.
///
/// Search is submit-driven — the singer presses the Search button or the
/// keyboard return key. Keystroke-driven search is forbidden because the
/// YouTube Data API quota is 100 calls per day (research.md R2, T053).
struct SearchView: View {

    @Bindable var viewModel: SearchViewModel
    var onSelect: (SongMetadata) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                resultsList
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Song title or YouTube link", text: $viewModel.queryText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    // Submit-driven: only fires on keyboard return, not on every keystroke.
                    viewModel.resolveDirectReference()
                }

            Button("Search") {
                viewModel.resolveDirectReference()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    // MARK: Results list

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.isLoading {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.lastError {
            errorView(error)
        } else if viewModel.results.isEmpty && !viewModel.queryText.isEmpty {
            emptyState
        } else {
            List(viewModel.results, id: \.id) { song in
                SongResultRow(song: song)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.select(song)
                        onSelect(song)
                    }
            }
            .listStyle(.plain)
        }
    }

    private func errorView(_ error: SearchError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: error.isMechanismSide ? "wrench.and.screwdriver" : "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(error.isMechanismSide ? .orange : .secondary)

            Text(error.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                viewModel.resolveDirectReference()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No results found")
                .foregroundStyle(.secondary)
            Text("Try a different search term or paste a YouTube link.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SongResultRow

/// A single search result row showing title, channel, and duration (FR-001).
struct SongResultRow: View {

    let song: SongMetadata

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(song.channelName, systemImage: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(formatDuration(song.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let url = song.thumbnailURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
            }
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 80, height: 45)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
