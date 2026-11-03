// T082 — SettingsView with lyrics opt-in toggle.
//
// The lyrics toggle defaults to OFF — no network request for text is made
// until the singer enables it (contracts/lyrics-provider.md Behavioural
// requirements, FR-022).
//
// Satisfies: FR-020, FR-022, FR-024

import SwiftUI
import SwiftData

struct SettingsView: View {

    @Bindable var settings: PerformanceSettings
    @AppStorage("lyricsProviderEnabled") private var lyricsProviderEnabled: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Lyrics") {
                    Toggle("Show Synchronized Lyrics", isOn: $lyricsProviderEnabled)
                    if lyricsProviderEnabled {
                        Text("Lyrics are fetched from LRCLIB (lrclib.net) when available. No account required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NavigationLink("Timing Offset") {
                            LyricsOffsetView(settings: settings)
                                .navigationTitle("Lyrics Timing")
                        }
                    }
                }

                Section("Display") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lyrics Font Size")
                            Spacer()
                            Text(String(format: "%.1f×", settings.lyricsFontScale))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $settings.lyricsFontScale,
                            in: PerformanceSettings.lyricsFontScaleRange
                        )
                    }
                }

                Section("Volume") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Output Volume")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.outputVolume * 100))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $settings.outputVolume,
                            in: PerformanceSettings.outputVolumeRange
                        )
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
