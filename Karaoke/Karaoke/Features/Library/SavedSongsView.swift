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
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if savedSongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle("Saved Songs")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
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
        EmptyStateView(
            icon: "arrow.down.circle",
            title: "No Saved Songs",
            message: "Save songs while connected so you can sing without the network."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var songList: some View {
        List {
            Section {
                storageSummaryCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Theme.Space.xs,
                        leading: Theme.Space.lg,
                        bottom: Theme.Space.md,
                        trailing: Theme.Space.lg
                    ))
            }

            Section {
                ForEach(savedSongs, id: \.songID) { saved in
                    SavedSongRow(saved: saved) {
                        songToDelete = saved
                        showDeleteConfirmation = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Theme.Space.xs,
                        leading: Theme.Space.lg,
                        bottom: Theme.Space.xs,
                        trailing: Theme.Space.lg
                    ))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            songToDelete = saved
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            } header: {
                SectionHeading(
                    title: "Saved for offline",
                    trailing: "\(savedSongs.count)"
                )
                .textCase(nil)
                .padding(.bottom, Theme.Space.xs)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background)
    }

    private var storageSummaryCard: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "internaldrive.fill")
                .font(.title3)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 40, height: 40)
                .background(Theme.Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Total Storage Used")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(totalStorageText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            Spacer()
        }
        .padding(Theme.Space.md)
        .card(Theme.Palette.surface)
    }

    private var totalStorageText: String {
        if let report = try? mediaStore.storageReport(context: modelContext) {
            return formatBytes(report.completedBytes)
        }
        let fallbackBytes = savedSongs
            .filter { $0.state == .complete }
            .reduce(Int64(0)) { $0 + $1.byteSize }
        return formatBytes(fallbackBytes)
    }

    private var storageLabel: some View {
        Text(totalStorageText)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.Palette.surface, in: Capsule())
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

/// A single row showing a saved song's title, size, download progress, and delete action.
private struct SavedSongRow: View {

    let saved: SavedSong
    var onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(songTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(saved.state == .failed ? Theme.Palette.mechanismIssue : Theme.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Theme.Space.sm) {
                        if !channelName.isEmpty {
                            Text(channelName)
                                .lineLimit(1)
                            Text("·")
                        }
                        stateIndicator
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: Theme.Hit.minimum, height: Theme.Hit.minimum)
                        .background(Theme.Palette.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
            }

            if saved.state == .downloading {
                downloadProgress
            } else if saved.state == .failed, let error = saved.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.mechanismIssue)
                    .lineLimit(2)
            }
        }
        .padding(Theme.Space.md)
        .frame(minHeight: Theme.Hit.control)
        .card(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(
                    saved.state == .failed ? Theme.Palette.mechanismIssue.opacity(0.6) : .clear,
                    lineWidth: saved.state == .failed ? 1.5 : 0
                )
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stateIndicator: some View {
        switch saved.state {
        case .complete:
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.success)
                Text(formatBytes(saved.byteSize))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(.caption.weight(.medium))

        case .downloading:
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.Palette.accent)
                Text(sizeProgressLabel)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(.caption.weight(.medium))

        case .pending:
            HStack(spacing: Theme.Space.xs) {
                ProgressView()
                    .tint(Theme.Palette.accent)
                    .scaleEffect(0.7)
                Text("Waiting…")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(.caption.weight(.medium))

        case .failed:
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.Palette.mechanismIssue)
                Text("Failed")
                    .foregroundStyle(Theme.Palette.mechanismIssue)
                if saved.byteSize > 0 {
                    Text("· \(formatBytes(saved.byteSize))")
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var sizeProgressLabel: String {
        if saved.byteSize > 0 {
            return "\(formatBytes(saved.downloadedBytes)) / \(formatBytes(saved.byteSize))"
        }
        return formatBytes(saved.downloadedBytes)
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .tint(Theme.Palette.accent)

            if let error = saved.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.mechanismIssue)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Helpers

    private var progressFraction: Double {
        guard saved.byteSize > 0 else { return 0 }
        return min(1.0, max(0.0, Double(saved.downloadedBytes) / Double(saved.byteSize)))
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
