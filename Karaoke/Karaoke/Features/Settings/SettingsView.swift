// T082, T132, T135 — SettingsView.
//
// T082: Lyrics opt-in toggle (defaults to OFF — no network request until enabled).
// T132: Link to SigningValidityView (FR-036).
// T135: Companion service address field and provider-preference control (T134).
//
// Satisfies: FR-020, FR-022, FR-024, FR-036

import SwiftUI
import SwiftData

struct SettingsView: View {

    @Bindable var settings: PerformanceSettings
    @AppStorage("lyricsProviderEnabled") private var lyricsProviderEnabled: Bool = false
    @AppStorage(CompanionSourceProvider.addressKey) private var companionAddress: String = ""
    @AppStorage("companionPreferred") private var companionPreferred: Bool = false

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

                // T135: Companion service configuration.
                Section {
                    TextField("http://192.168.1.x:7979", text: $companionAddress)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Toggle("Prefer companion over on-device", isOn: $companionPreferred)
                        .onChange(of: companionPreferred) { _, preferred in
                            NotificationCenter.default.post(
                                name: .companionPreferenceChanged,
                                object: preferred
                            )
                        }

                    Text("The companion service resolves audio server-side. Use it when on-device resolution breaks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Companion Service")
                } footer: {
                    Text("Run Tools/companion-service/run.sh on your Mac. Enter the Mac's local IP address above.")
                        .font(.caption)
                }

                Section("App") {
                    NavigationLink("Signing Validity") {
                        SigningValidityView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

extension Notification.Name {
    static let companionPreferenceChanged = Notification.Name("companionPreferenceChanged")
}
