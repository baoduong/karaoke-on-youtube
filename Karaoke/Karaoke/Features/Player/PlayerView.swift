// T058 — PlayerView.
//
// Transport controls, position display, volume control, and active route indicator.
//
// Position is read from PlaybackSession.positionSeconds, which is driven by the
// player's own clock — never a wall-clock timer (audio-pipeline.md requirement 1).
//
// Satisfies: FR-009, FR-013, FR-014, FR-017

import SwiftUI

// MARK: - PlayerView

/// The player screen. Shows transport controls, position, volume, and route.
///
/// Position comes from the player's clock via PlaybackSession — never a
/// wall-clock timer (audio-pipeline.md Behavioural requirement 1).
struct PlayerView: View {

    @Bindable var session: PlaybackSession
    var onDismiss: (() -> Void)?

    @State private var volume: Double = 1.0
    @State private var showQualityDetail = false

    var body: some View {
        VStack(spacing: 0) {
            // Route indicator bar
            routeIndicator

            Spacer()

            // Song info
            songInfo

            Spacer()

            // Position and seek
            positionBar

            // Transport controls
            transportControls

            // Volume
            volumeControl

            Spacer(minLength: 20)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showQualityDetail) {
            QualityDetailView(
                rendition: session.selectedRendition,
                outputRoute: session.outputRoute
            )
        }
    }

    // MARK: Route indicator (FR-014)

    private var routeIndicator: some View {
        HStack {
            Image(systemName: routeIcon)
                .foregroundStyle(session.outputRoute.degradesQuality ? .orange : .green)

            Text(routeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            if session.outputRoute.degradesQuality {
                Text("(re-encoded)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button {
                showQualityDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var routeIcon: String {
        switch session.outputRoute.kind {
        case .bluetoothA2DP: return "hifispeaker.fill"
        case .builtInSpeaker: return "speaker.wave.2.fill"
        case .wiredLineOut: return "headphones"
        case .usbAudio: return "cable.connector"
        case .airPlay: return "airplayvideo"
        case .other: return "speaker.fill"
        }
    }

    private var routeLabel: String {
        switch session.outputRoute.kind {
        case .bluetoothA2DP: return "Bluetooth A2DP"
        case .builtInSpeaker: return "Built-in Speaker"
        case .wiredLineOut: return "Wired Output"
        case .usbAudio: return "USB Audio"
        case .airPlay: return "AirPlay"
        case .other: return "Audio Output"
        }
    }

    // MARK: Song info

    private var songInfo: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            if let id = session.songID {
                Text(id)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                Text("No song loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let rendition = session.selectedRendition {
                Text(renditionSummary(rendition))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func renditionSummary(_ rendition: AudioRendition) -> String {
        var parts: [String] = []
        switch rendition.codec {
        case .aac: parts.append("AAC")
        case .opus: parts.append("Opus")
        case .vorbis: parts.append("Vorbis")
        case .other(let s): parts.append(s)
        }
        if let bps = rendition.averageBitrateBps {
            parts.append("\(bps / 1000) kbps")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Position bar

    private var positionBar: some View {
        VStack(spacing: 4) {
            if session.durationSeconds > 0 {
                Slider(
                    value: Binding(
                        get: { session.positionSeconds },
                        set: { newValue in
                            Task { await session.seek(to: newValue) }
                        }
                    ),
                    in: 0...max(session.durationSeconds, 1)
                )
            } else {
                Slider(value: .constant(0), in: 0...1)
                    .disabled(true)
            }

            HStack {
                Text(formatTime(session.positionSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(session.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Transport controls

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button {
                Task { await session.seek(to: max(0, session.positionSeconds - 10)) }
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.title2)
            }
            .disabled(session.songID == nil)

            playPauseButton

            Button {
                let target = min(session.durationSeconds, session.positionSeconds + 10)
                Task { await session.seek(to: target) }
            } label: {
                Image(systemName: "goforward.10")
                    .font(.title2)
            }
            .disabled(session.songID == nil)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var playPauseButton: some View {
        switch session.state {
        case .playing:
            Button {
                session.pause()
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 56))
            }

        case .buffering, .resolving:
            ProgressView()
                .scaleEffect(1.5)
                .frame(width: 56, height: 56)

        default:
            Button {
                session.resume()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56))
            }
            .disabled(session.songID == nil)
        }
    }

    // MARK: Volume control (FR-013)

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)

            Slider(value: $volume, in: 0...1) { _ in
                session.setVolume(volume)
            }

            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
