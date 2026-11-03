import SwiftUI

/// Placeholder shell established by Phase 1 setup.
///
/// Replaced by the real search and player surfaces in Phase 4 (User Story 1).
/// It exists now so the target compiles and so `xcodegen generate` produces a
/// runnable scheme to verify the build settings.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Karaoke")
                .font(.largeTitle.weight(.semibold))

            Text("Project skeleton. Search and playback arrive in Phase 4.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
