// T080 — LyricsOffsetView.
//
// Manual display-versus-audio trim control bound to manualLyricsOffsetMs.
// Range: -2000...+2000 ms (FR-020, PerformanceSettings).
// Added ON TOP OF the automatic route delay — reset to 0 restores automatic
// behaviour (data-model.md PerformanceSettings, contracts/lyrics-provider.md Rule 4).
//
// Satisfies: FR-020

import SwiftUI
import SwiftData

struct LyricsOffsetView: View {

    @Bindable var settings: PerformanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lyrics Timing Offset")
                    .font(.headline)
                Spacer()
                Text("\(settings.manualLyricsOffsetMs) ms")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(settings.manualLyricsOffsetMs) },
                    set: { settings.manualLyricsOffsetMs = Int($0) }
                ),
                in: Double(PerformanceSettings.manualLyricsOffsetMsRange.lowerBound)...Double(PerformanceSettings.manualLyricsOffsetMsRange.upperBound),
                step: 50
            )

            HStack {
                Text("Earlier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    settings.manualLyricsOffsetMs = 0
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Spacer()
                Text("Later")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Adjusts lyrics timing on top of the automatic Bluetooth delay compensation.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
