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
        withAnimation(.easeIn(duration: 0.3)) {
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
struct LyricsView: View {

    let viewModel: LyricsViewModel
    let fontScale: Double

    private static let readAheadLines = 3
    private static let readBehindLines = 2

    var body: some View {
        if viewModel.isVisible, let track = viewModel.track {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .center, spacing: 12 * fontScale) {
                        ForEach(track.lines.indices, id: \.self) { idx in
                            lineView(
                                line: track.lines[idx],
                                isCurrent: viewModel.currentPosition.lineIndex == idx,
                                isNearby: isNearby(idx: idx),
                                currentWordIndex: viewModel.currentPosition.lineIndex == idx
                                    ? viewModel.currentPosition.wordIndex
                                    : nil
                            )
                            .id(idx)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
                .onChange(of: viewModel.currentPosition.lineIndex) { _, newIdx in
                    if let idx = newIdx {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

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
                .font(.system(size: 24 * fontScale, weight: isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                .opacity(isNearby ? 1.0 : 0.4)
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

    private func wordHighlightLine(
        line: LyricsLineData,
        currentWordIndex: Int?,
        isCurrent: Bool,
        isNearby: Bool
    ) -> some View {
        FlowLayout(spacing: 4 * fontScale) {
            ForEach(line.words.indices, id: \.self) { wi in
                let word = line.words[wi]
                let isCurrentWord = currentWordIndex == wi
                Text(word.text)
                    .font(.system(size: 24 * fontScale, weight: isCurrentWord ? .bold : .regular))
                    .foregroundStyle(isCurrentWord ? Color.accentColor : (isCurrent ? Color.primary : Color.secondary))
                    .opacity(isNearby ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.1), value: isCurrentWord)
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
