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

    private var isPlaying: Bool { session.state == .playing }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            songInfo
            transportControls
        }
        // Capped rather than stretched. At full iPad width a 16:9 video
        // becomes a short wide band with the controls marooned beneath it,
        // and the whole screen reads as mostly empty.
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
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

        }
        .frame(maxWidth: .infinity)
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
}
