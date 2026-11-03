import SwiftUI
import SwiftData

// MARK: - SavedSongsView (T126)

/// Lists all saved songs with per-song size, download progress, and individual
/// removal (FR-029, FR-031, US5 acceptance scenario 4).
///
/// Uses @Observable / @Query for live updates — no ObservableObject.
struct SavedSongsView: View {

    // MARK: Environment

    @Environment(\.modelContext) private var modelContext

    // MARK: Queries

    @Query(sort: \SavedSong.savedAt, order: .reverse)
    private var savedSongs: [SavedSong]

    // MARK: State

    @State private var songToDelete: SavedSong?
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false

    // MARK: Dependencies

    private let mediaStore: MediaStore
    private let coordinator: SaveCoordinator

    // MARK: Init

    init(mediaStore: MediaStore, coordinator: SaveCoordinator) {
        self.mediaStore = mediaStore
        self.coordinator = coordinator
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if savedSongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle("Saved Songs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    storageLabel
                }
            }
            .confirmationDialog(
                "Remove Song",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let song = songToDelete {
                        performDelete(song)
                    }
                }
                Button("Cancel", role: .cancel) {
                    songToDelete = nil
                }
            } message: {
                if let song = songToDelete {
                    Text("Remove \"\(songTitle(for: song))\" from offline storage?")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred.")
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "No Saved Songs",
            systemImage: "arrow.down.circle",
            description: Text("Save songs while connected so you can sing without the network.")
        )
    }

    private var songList: some View {
        List {
            ForEach(savedSongs, id: \.songID) { saved in
                SavedSongRow(saved: saved)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            songToDelete = saved
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var storageLabel: some View {
        Group {
            if let report = try? mediaStore.storageReport(context: modelContext) {
                Text(formatBytes(report.completedBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func performDelete(_ saved: SavedSong) {
        let songID = saved.songID
        Task {
            do {
                try await coordinator.delete(songID: songID, context: modelContext)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
        songToDelete = nil
    }

    // MARK: - Helpers

    private func songTitle(for saved: SavedSong) -> String {
        let targetID = saved.songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        let songs = (try? modelContext.fetch(descriptor)) ?? []
        return songs.first?.title ?? saved.songID
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - SavedSongRow

/// A single row showing a saved song's title, size, and download progress.
private struct SavedSongRow: View {

    let saved: SavedSong

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(songTitle)
                        .font(.body)
                        .lineLimit(1)

                    Text(channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                stateIndicator
            }

            if saved.state == .downloading {
                downloadProgress
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stateIndicator: some View {
        switch saved.state {
        case .complete:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(formatBytes(saved.byteSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .downloading:
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
                Text(formatBytes(saved.downloadedBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .pending:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Waiting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .tint(.blue)

            if let error = saved.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Helpers

    private var progressFraction: Double {
        guard saved.byteSize > 0 else { return 0 }
        return Double(saved.downloadedBytes) / Double(saved.byteSize)
    }

    private var songTitle: String {
        let targetID = saved.songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        let songs = (try? modelContext.fetch(descriptor)) ?? []
        return songs.first?.title ?? saved.songID
    }

    private var channelName: String {
        let targetID = saved.songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        let songs = (try? modelContext.fetch(descriptor)) ?? []
        return songs.first?.channelName ?? ""
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
