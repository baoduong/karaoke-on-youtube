// T081 — SourceVideoView.
//
// Video display path for sources that carry the words in the image.
// Most karaoke sources carry the words in the video image — this is the
// primary display mode, not a fallback (contracts/lyrics-provider.md Scope).
//
// Kept in step with the audio via the playback session's position.
//
// Satisfies: FR-021

import SwiftUI
import AVKit

/// Displays the video for a karaoke source that carries lyrics in the image.
///
/// This is the primary display for most sources. The synchronized text layer
/// (LyricsView) is an enhancement layered on top when a provider is enabled.
struct SourceVideoView: View {

    let player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
    }
}
