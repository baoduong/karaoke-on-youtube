import SwiftUI

/// The player screen.
///
/// The video is the hero, not decoration: most karaoke uploads burn the words
/// into the picture, so the video *is* the lyrics. Everything else is arranged
/// around it, and no control covers its centre, where the text sits.
///
/// Position comes from the player's clock via PlaybackSession — never a
/// wall-clock timer (audio-pipeline.md Behavioural requirement 1).
struct PlayerView: View {

    @Bindable var session: PlaybackSession
    /// The chosen song. The session only knows an id; the title and channel
    /// the singer recognises live here.
    var song: SongMetadata?
    var onDismiss: (() -> Void)?

    @State private var volume: Double = 1.0
    @State private var showQualityDetail = false

    private var isPlaying: Bool { session.state == .playing }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            videoStage
            songInfo
            positionBar
            transportControls
            volumeControl
        }
        // Capped rather than stretched. At full iPad width a 16:9 video
        // becomes a short wide band with the controls marooned beneath it,
        // and the whole screen reads as mostly empty.
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.lg)
        .sheet(isPresented: $showQualityDetail) {
            QualityDetailView(
                rendition: session.selectedRendition,
                outputRoute: session.outputRoute
            )
        }
    }

    // MARK: Video stage

    /// 16:9 at full width, with the route badge overlaid in a corner so it
    /// costs no vertical space and never sits over the centre of the frame.
    private var videoStage: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let player = session.videoPlayer, session.songID != nil {
                    SourceVideoView(player: player)
                } else {
                    ZStack {
                        Theme.Palette.surface
                        Image(systemName: "music.note.tv")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            routeBadge.padding(Theme.Space.sm)
        }
    }

    // MARK: Route badge (FR-014)

    /// Names the route and, when it re-encodes, says so.
    ///
    /// Bluetooth compresses the audio again before transmitting. The app
    /// discloses that rather than claiming a bitrate the link discards — but
    /// as a calm note, not an alarm: it is the normal, chosen setup.
    private var routeBadge: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: routeIcon)
                .font(.caption2)
            Text(routeName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            if session.outputRoute.degradesQuality {
                Text("re-encoded")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Button {
                showQualityDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption2)
            }
            .accessibilityLabel("Audio quality detail")
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var routeName: String {
        switch session.outputRoute.kind {
        case .bluetoothA2DP:  return "Bluetooth"
        case .airPlay:        return "AirPlay"
        case .usbAudio:       return "USB"
        case .wiredLineOut:   return "Wired"
        case .builtInSpeaker: return "Phone speaker"
        case .other:          return "Output"
        }
    }

    private var routeIcon: String {
        switch session.outputRoute.kind {
        case .bluetoothA2DP:  return "hifispeaker.fill"
        case .airPlay:        return "airplayaudio"
        case .usbAudio:       return "cable.connector"
        case .wiredLineOut:   return "headphones"
        case .builtInSpeaker: return "iphone"
        case .other:          return "speaker.wave.2"
        }
    }

    // MARK: Song info

    private var songInfo: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(song?.title ?? "Nothing playing")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let channel = song?.channelName, !channel.isEmpty {
                Text(channel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }

            if let rendition = session.selectedRendition {
                Text(renditionSummary(rendition))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func renditionSummary(_ rendition: AudioRendition) -> String {
        var parts = [containerLabel(rendition.container), codecLabel(rendition.codec)]
        if let bitrate = rendition.averageBitrateBps {
            parts.append("\(bitrate / 1000) kbps")
        }
        return parts.joined(separator: " · ")
    }

    private func containerLabel(_ container: Container) -> String {
        switch container {
        case .m4a:              return "M4A"
        case .webm:             return "WebM"
        case .mp4:              return "MP4"
        case .other(let raw):   return raw.uppercased()
        }
    }

    private func codecLabel(_ codec: Codec) -> String {
        switch codec {
        case .aac:              return "AAC"
        case .opus:             return "Opus"
        case .vorbis:           return "Vorbis"
        case .other(let raw):   return raw.uppercased()
        }
    }

    // MARK: Position

    private var positionBar: some View {
        VStack(spacing: Theme.Space.xs) {
            Slider(
                value: Binding(
                    get: { min(session.positionSeconds, max(session.durationSeconds, 1)) },
                    set: { newValue in Task { await session.seek(to: newValue) } }
                ),
                in: 0...max(session.durationSeconds, 1)
            )
            .tint(Theme.Palette.accent)
            .disabled(session.durationSeconds <= 0)

            HStack {
                Text(session.positionSeconds.asDurationLabel)
                Spacer()
                Text(session.durationSeconds.asDurationLabel)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    // MARK: Transport

    /// Play/pause is oversized on purpose: it is pressed one-handed while the
    /// other hand holds a microphone.
    private var transportControls: some View {
        HStack(spacing: Theme.Space.xl) {
            transportButton("gobackward.10") {
                Task { await session.seek(to: max(0, session.positionSeconds - 10)) }
            }

            Button {
                if isPlaying { session.pause() } else { session.resume() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: Theme.Hit.primaryControl, height: Theme.Hit.primaryControl)
                    .background(Theme.Palette.accent, in: Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            transportButton("goforward.10") {
                Task { await session.seek(to: min(session.durationSeconds, session.positionSeconds + 10)) }
            }
        }
    }

    private func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: Theme.Hit.control, height: Theme.Hit.control)
        }
    }

    // MARK: Volume

    private var volumeControl: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "speaker.fill")
            Slider(value: $volume, in: 0...1) { editing in
                if !editing { session.setVolume(volume) }
            }
            .tint(Theme.Palette.accent)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(.bottom, Theme.Space.sm)
    }
}
