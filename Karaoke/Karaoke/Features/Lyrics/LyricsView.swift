// T077, T078, T079 — LyricsView.
//
// Driven by a display-refresh callback that ASKS the player for position.
// Never keeps its own position — that is how karaoke displays drift.
//
// T078: current-line and current-word highlighting with read-ahead.
// T079: text scaling bound to lyricsFontScale (0.5…3.0).
//
// Word-level highlight is opportunistic — the UI looks completely normal when
// word timing is absent, which is the common case (research.md R5).
//
// Satisfies: FR-023, FR-024, contracts/lyrics-provider.md Rendering requirements

import SwiftUI

// MARK: - LyricsViewModel

/// Drives the lyrics display. Holds the resolved position and the track.
@MainActor
@Observable
final class LyricsViewModel {

    var track: LyricsTrackData?
    var currentPosition: LyricsPosition = LyricsPosition(lineIndex: nil, wordIndex: nil, progressWithinWord: 0)
    var isVisible: Bool = false

    private var timeline: LyricsTimeline?
    private var previousHint: Int?

    func setTrack(_ newTrack: LyricsTrackData?) {
        track = newTrack
        timeline = newTrack.map { LyricsTimeline(track: $0) }
        previousHint = nil
        currentPosition = LyricsPosition(lineIndex: nil, wordIndex: nil, progressWithinWord: 0)
        withAnimation(.easeIn(duration: 0.25)) {
            isVisible = newTrack != nil
        }
    }

    /// Called at display-refresh rate by the player's position callback.
    /// Asks the pipeline for position — never keeps its own clock.
    func update(
        positionSeconds: Double,
        outputLatencyMs: Double,
        globalOffsetMs: Int,
        manualLyricsOffsetMs: Int
    ) {
        guard let tl = timeline else { return }
        let pos = tl.position(
            atPositionSeconds: positionSeconds,
            outputLatencyMs: outputLatencyMs,
            globalOffsetMs: globalOffsetMs,
            manualLyricsOffsetMs: manualLyricsOffsetMs,
            hint: previousHint
        )
        previousHint = pos.lineIndex
        currentPosition = pos
    }
}

// MARK: - LyricsView

/// Displays synchronized lyrics with current-line and current-word highlighting.
///
/// Read-ahead: shows lines before and after the current one so the singer can
/// prepare. A display showing only the current line is useless for singing
/// (contracts/lyrics-provider.md Rendering requirements).
///
/// Most karaoke uploads burn lyrics directly into the video picture and have no
/// separate synchronised LRC track. When `track` is nil or has no lines, the
/// view renders a calm, deliberate `EmptyStateView` card so the absence of
/// text lyrics reads as the normal case rather than a missing component.
struct LyricsView: View {

    let viewModel: LyricsViewModel
    let fontScale: Double

    private static let readAheadLines = 3
    private static let readBehindLines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "Lyrics")

            if viewModel.isVisible, let track = viewModel.track, !track.lines.isEmpty {
                synchronizedLyricsCard(track: track)
            } else {
                noLyricsCard
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    // MARK: - Synchronized Lyrics Stage

    private func synchronizedLyricsCard(track: LyricsTrackData) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: Theme.Space.md * fontScale) {
                    ForEach(track.lines.indices, id: \.self) { idx in
                        let isCurrent = viewModel.currentPosition.lineIndex == idx
                        lineView(
                            line: track.lines[idx],
                            isCurrent: isCurrent,
                            isNearby: isNearby(idx: idx),
                            currentWordIndex: isCurrent
                                ? viewModel.currentPosition.wordIndex
                                : nil
                        )
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, isCurrent ? Theme.Space.sm : Theme.Space.xs)
                        .frame(maxWidth: .infinity)
                        .background(
                            isCurrent ? Theme.Palette.surfaceRaised : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        )
                        .id(idx)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.lg)
            }
            .frame(minHeight: 220, maxHeight: 320)
            .onChange(of: viewModel.currentPosition.lineIndex) { _, newIdx in
                if let idx = newIdx {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
        .card(Theme.Palette.surface)
        .transition(.opacity)
    }

    // MARK: - Normal No-Lyrics State

    private var noLyricsCard: some View {
        EmptyStateView(
            icon: "music.note.tv",
            title: "Lyrics are in the video",
            message: "No separate text track for this song — follow the words on the video stage above."
        )
        .frame(maxWidth: .infinity)
        .card(Theme.Palette.surface)
    }

    // MARK: - Line Rendering

    private func isNearby(idx: Int) -> Bool {
        guard let current = viewModel.currentPosition.lineIndex else { return true }
        let diff = idx - current
        return diff >= -Self.readBehindLines && diff <= Self.readAheadLines
    }

    @ViewBuilder
    private func lineView(
        line: LyricsLineData,
        isCurrent: Bool,
        isNearby: Bool,
        currentWordIndex: Int?
    ) -> some View {
        if line.words.isEmpty || currentWordIndex == nil {
            // Line-level highlight (the common case — research.md R5).
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: (isCurrent ? 24 : 20) * fontScale, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(lineColor(isCurrent: isCurrent, isNearby: isNearby))
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.15), value: isCurrent)
        } else {
            // Word-level highlight (opportunistic).
            wordHighlightLine(
                line: line,
                currentWordIndex: currentWordIndex,
                isCurrent: isCurrent,
                isNearby: isNearby
            )
        }
    }

    private func lineColor(isCurrent: Bool, isNearby: Bool) -> Color {
        if isCurrent {
            return Theme.Palette.accent
        } else if isNearby {
            return Theme.Palette.textSecondary
        } else {
            return Theme.Palette.textTertiary
        }
    }

    private func wordHighlightLine(
        line: LyricsLineData,
        currentWordIndex: Int?,
        isCurrent: Bool,
        isNearby: Bool
    ) -> some View {
        FlowLayout(spacing: 5 * fontScale) {
            ForEach(line.words.indices, id: \.self) { wi in
                let word = line.words[wi]
                let isCurrentWord = currentWordIndex == wi
                Text(word.text)
                    .font(.system(size: (isCurrent ? 24 : 20) * fontScale, weight: isCurrentWord ? .bold : (isCurrent ? .semibold : .medium)))
                    .foregroundStyle(
                        isCurrentWord
                            ? Theme.Palette.accent
                            : (isCurrent ? Theme.Palette.textPrimary : lineColor(isCurrent: false, isNearby: isNearby))
                    )
                    .animation(.easeInOut(duration: 0.12), value: isCurrentWord)
            }
        }
    }
}

// MARK: - FlowLayout

/// A simple horizontal flow layout that wraps words onto new lines.
private struct FlowLayout: Layout {
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
