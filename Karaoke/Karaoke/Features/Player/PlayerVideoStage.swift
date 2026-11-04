import AVFoundation
import SwiftUI

/// The video, pinned above the scrolling part of the player.
///
/// It lives outside the scroll view rather than inside it because on most
/// karaoke uploads the words are burned into the picture: the video *is* the
/// lyrics. Letting it scroll away while someone is singing would remove the
/// thing they are reading. The controls and suggestions scroll beneath it.
///
/// Edge to edge, with no horizontal padding, so the frame is as large as the
/// screen allows. The 760pt cap only engages on iPad; on a phone the screen is
/// narrower than that, so the video is full-bleed there.
struct PlayerVideoStage: View {

    let player: AVPlayer?
    let isLoaded: Bool
    let route: OutputRoute
    var isStarting: Bool = false
    var onShowQualityDetail: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let player, isLoaded {
                    SourceVideoView(player: player)
                } else {
                    ZStack {
                        Theme.Palette.surface
                        if isStarting {
                            startingIndicator
                        } else {
                            Image(systemName: "music.note.tv")
                                .font(Theme.Typography.glyphEmpty)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

            routeBadge.padding(Theme.Space.sm)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private var startingIndicator: some View {
        VStack(spacing: Theme.Space.sm) {
            ProgressView()
                .tint(Theme.Palette.accent)
            Text("Starting…")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    /// Names the route and, when it re-encodes, says so.
    ///
    /// Bluetooth compresses the audio again before transmitting. The app
    /// discloses that rather than claiming a bitrate the link discards — but
    /// as a calm note, not an alarm: it is the normal, chosen setup.
    private var routeBadge: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: routeIcon)
                .font(Theme.Typography.caption)
            Text(routeName)
                .font(Theme.Typography.caption)
                .lineLimit(1)
            if route.degradesQuality {
                Text("re-encoded")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Button(action: onShowQualityDetail) {
                Image(systemName: "info.circle")
                    .font(Theme.Typography.caption)
            }
            .accessibilityLabel("Audio quality detail")
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var routeName: String {
        switch route.kind {
        case .bluetoothA2DP:  return "Bluetooth"
        case .airPlay:        return "AirPlay"
        case .usbAudio:       return "USB"
        case .wiredLineOut:   return "Wired"
        case .builtInSpeaker: return "Phone speaker"
        case .other:          return "Output"
        }
    }

    private var routeIcon: String {
        switch route.kind {
        case .bluetoothA2DP:  return "hifispeaker.fill"
        case .airPlay:        return "airplayaudio"
        case .usbAudio:       return "cable.connector"
        case .wiredLineOut:   return "headphones"
        case .builtInSpeaker: return "iphone"
        case .other:          return "speaker.wave.2"
        }
    }
}
