import SwiftUI

/// Personal karaoke player. Searches YouTube for backing tracks and plays them
/// ad-free over Bluetooth to a portable PA speaker.
///
/// Two scope decisions shape this whole app:
///
/// 1. **Playback only.** The PA speaker owns the microphone, its preamp, its
///    effects, and the vocal/music mix, all in hardware. This app never
///    captures audio. `Info.plist` deliberately omits
///    `NSMicrophoneUsageDescription` so the OS enforces that rather than
///    trusting us to remember.
///
/// 2. **No pitch or tempo processing.** Songs play as published. Together with
///    (1) this removes any reason to own an audio processing graph, so there is
///    no render thread and no real-time code anywhere in this target.
@main
struct KaraokeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
