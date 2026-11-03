// T116 — QueueView.
//
// Displays the queue with drag-to-reorder and swipe-to-remove.
//
// FR-025: Users MUST be able to queue multiple songs, view the queue order,
// reorder it, and remove entries.
// Acceptance 3: reordering or removing an entry must not disturb the currently
// playing song.

import SwiftUI
import SwiftData

// MARK: - QueueView

/// Displays the ordered list of songs awaiting performance.
///
/// Drag-to-reorder and swipe-to-remove operate only on `waiting` entries.
/// The `current` entry is shown but cannot be reordered — it is pinned at
/// the top of the active section (T113: non-disruptive mutation).
struct QueueView: View {

    // MARK: - Dependencies

    @Bindable var service: QueueService

    @Environment(\.modelContext) private var context

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if service.entries.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .navigationTitle("Queue")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "Queue is empty",
            systemImage: "music.note.list",
            description: Text("Add songs from search results to build your set list.")
        )
    }

    private var queueList: some View {
        List {
            // Current entry — shown separately, cannot be reordered.
            if let current = service.current {
                Section("Now Playing") {
                    QueueRowView(entry: current, context: context)
                        .listRowBackground(Color.accentColor.opacity(0.08))
                }
            }

            // Waiting entries — drag-to-reorder and swipe-to-remove.
            if !service.waiting.isEmpty {
                Section("Up Next") {
                    ForEach(service.waiting, id: \.id) { entry in
                        QueueRowView(entry: entry, context: context)
                    }
                    .onMove { source, destination in
                        service.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        let waitingEntries = service.waiting
                        for index in offsets {
                            service.remove(id: waitingEntries[index].id)
                        }
                    }
                }
            }

            // History — played, skipped, failed entries (informational).
            let history = service.entries.filter {
                $0.state == .played || $0.state == .skipped || $0.state == .failed
            }
            if !history.isEmpty {
                Section("History") {
                    ForEach(history, id: \.id) { entry in
                        QueueRowView(entry: entry, context: context)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            EditButton()
        }
    }
}

// MARK: - QueueRowView

/// A single row in the queue list.
///
/// Looks up the Song by `songID` to display title, channel, and duration.
/// Falls back to the raw `songID` when the Song is not in the local store
/// (should not happen in normal operation — StoreReconciler repairs orphans
/// at launch, data-model invariant 1).
private struct QueueRowView: View {

    let entry: QueueEntry
    let context: ModelContext

    var body: some View {
        HStack(spacing: 12) {
            stateIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(songTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(songSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let duration = songDuration {
                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Song lookup

    private var song: Song? {
        let targetID = entry.songID
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private var songTitle: String {
        song?.title ?? entry.songID
    }

    private var songSubtitle: String {
        song?.channelName ?? ""
    }

    private var songDuration: String? {
        guard let seconds = song?.durationSeconds else { return nil }
        return formatDuration(seconds)
    }

    // MARK: - State icon

    private var stateIcon: some View {
        Group {
            switch entry.state {
            case .current:
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
            case .waiting:
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            case .played:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .skipped:
                Image(systemName: "forward.fill")
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .imageScale(.medium)
        .frame(width: 24)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
