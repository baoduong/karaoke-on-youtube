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

    /// Tapping any row plays it, history included — a set list gets sung again.
    var onPlay: ((QueueEntry) -> Void)?

    @Environment(\.modelContext) private var context

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                if service.entries.isEmpty {
                    EmptyStateView(
                        icon: "music.note.list",
                        title: "Queue is empty",
                        message: "Add songs from search results to build your set list."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    queueList
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
            .toolbar {
                if !service.waiting.isEmpty {
                    EditButton()
                        .tint(Theme.Palette.accent)
                }
            }
        }
    }

    // MARK: - Subviews

    /// One tappable row, with the insets every section shares.
    private func row(_ entry: QueueEntry) -> some View {
        Button {
            onPlay?(entry)
        } label: {
            QueueRowView(entry: entry, context: context)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: Theme.Space.xs,
            leading: Theme.Space.lg,
            bottom: Theme.Space.xs,
            trailing: Theme.Space.lg
        ))
    }

    private var queueList: some View {
        List {
            // Current entry — shown separately, cannot be reordered.
            if let current = service.current {
                Section {
                    row(current)
                } header: {
                    SectionHeading(title: "Now Playing")
                        .textCase(nil)
                        .padding(.bottom, Theme.Space.xs)
                }
            }

            // Waiting entries — drag-to-reorder and swipe-to-remove.
            if !service.waiting.isEmpty {
                Section {
                    ForEach(service.waiting, id: \.id) { entry in
                        row(entry)
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
                } header: {
                    SectionHeading(
                        title: "Up Next",
                        trailing: "\(service.waiting.count)"
                    )
                    .textCase(nil)
                    .padding(.bottom, Theme.Space.xs)
                }
            }

            // History — played, skipped, failed entries (informational).
            let history = service.entries.filter {
                $0.state == .played || $0.state == .skipped || $0.state == .failed
            }
            if !history.isEmpty {
                Section {
                    ForEach(history, id: \.id) { entry in
                        row(entry)
                    }
                } header: {
                    SectionHeading(title: "History")
                        .textCase(nil)
                        .padding(.bottom, Theme.Space.xs)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background)
    }
}

// MARK: - QueueRowView

/// A single row in the queue list.
///
/// The five entry states use distinct surface treatments, badges, and opacity
/// so a singer glancing from across the room can tell what is playing now,
/// what is queued, what already played or was skipped, and what failed to load.
private struct QueueRowView: View {

    let entry: QueueEntry
    let context: ModelContext

    private var isDimmed: Bool {
        entry.state == .played || entry.state == .skipped
    }

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            stateIcon

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(songTitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Theme.Space.sm) {
                    if let badge = stateBadgeText {
                        Text(badge)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(badgeForegroundColor)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, 2)
                            .background(badgeBackgroundColor, in: Capsule())
                    }

                    if !songSubtitle.isEmpty {
                        Text(songSubtitle)
                            .lineLimit(1)
                    }

                    if let seconds = song?.durationSeconds {
                        if !songSubtitle.isEmpty {
                            Text("·")
                        }
                        Text(seconds.asDurationLabel)
                            .monospacedDigit()
                    }
                }
                .font(Theme.Typography.secondary)
                .foregroundStyle(subtitleColor)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .frame(minHeight: Theme.Hit.control)
        .card(cardColor)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(borderColor, lineWidth: entry.state == .current || entry.state == .failed ? 1.5 : 0)
        )
        .opacity(isDimmed ? 0.52 : 1.0)
    }

    // MARK: - Visual Styling per State

    private var cardColor: Color {
        switch entry.state {
        case .current:
            return Theme.Palette.surfaceRaised
        case .waiting, .played, .skipped, .failed:
            return Theme.Palette.surface
        }
    }

    private var borderColor: Color {
        switch entry.state {
        case .current:
            return Theme.Palette.accent
        case .failed:
            return Theme.Palette.mechanismIssue.opacity(0.6)
        case .waiting, .played, .skipped:
            return .clear
        }
    }

    private var titleColor: Color {
        switch entry.state {
        case .current:
            return Theme.Palette.accent
        case .waiting:
            return Theme.Palette.textPrimary
        case .played, .skipped:
            return Theme.Palette.textSecondary
        case .failed:
            return Theme.Palette.mechanismIssue
        }
    }

    private var subtitleColor: Color {
        switch entry.state {
        case .current, .waiting:
            return Theme.Palette.textSecondary
        case .played, .skipped:
            return Theme.Palette.textTertiary
        case .failed:
            return Theme.Palette.mechanismIssue.opacity(0.85)
        }
    }

    private var stateBadgeText: String? {
        switch entry.state {
        case .current:
            return "NOW PLAYING"
        case .waiting:
            return nil
        case .played:
            return "Played"
        case .skipped:
            return "Skipped"
        case .failed:
            return "Failed"
        }
    }

    private var badgeForegroundColor: Color {
        switch entry.state {
        case .current:
            return .black
        case .waiting:
            return Theme.Palette.textSecondary
        case .played:
            return Theme.Palette.success
        case .skipped:
            return Theme.Palette.textSecondary
        case .failed:
            return Theme.Palette.mechanismIssue
        }
    }

    private var badgeBackgroundColor: Color {
        switch entry.state {
        case .current:
            return Theme.Palette.accent
        case .waiting:
            return Theme.Palette.surfaceRaised
        case .played:
            return Theme.Palette.success.opacity(0.16)
        case .skipped:
            return Theme.Palette.surfaceRaised
        case .failed:
            return Theme.Palette.mechanismIssue.opacity(0.18)
        }
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

    // MARK: - State icon

    private var stateIcon: some View {
        ZStack {
            Circle()
                .fill(iconCircleColor)
                .frame(width: 36, height: 36)

            Group {
                switch entry.state {
                case .current:
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.black)
                case .waiting:
                    Image(systemName: "music.note")
                        .foregroundStyle(Theme.Palette.textSecondary)
                case .played:
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Palette.success)
                case .skipped:
                    Image(systemName: "forward.fill")
                        .foregroundStyle(Theme.Palette.textSecondary)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Palette.mechanismIssue)
                }
            }
            .font(Theme.Typography.secondary)
        }
    }

    private var iconCircleColor: Color {
        switch entry.state {
        case .current:
            return Theme.Palette.accent
        case .waiting, .skipped:
            return Theme.Palette.surfaceRaised
        case .played:
            return Theme.Palette.success.opacity(0.16)
        case .failed:
            return Theme.Palette.mechanismIssue.opacity(0.18)
        }
    }
}
