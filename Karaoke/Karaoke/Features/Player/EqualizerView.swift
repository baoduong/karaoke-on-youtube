import SwiftUI

/// The tone control (FR-043).
///
/// Presented as a sheet from the player rather than buried in Settings,
/// because the moment a singer notices a song sounds wrong is the moment it
/// is playing — and the whole point of the feature is not having to walk to
/// the PA.
struct EqualizerView: View {

    @Binding var settings: EqualizerSettings

    /// False when the platform refused the tap. The sheet then explains
    /// instead of offering sliders that move but change nothing (Principle VI).
    let isAvailable: Bool

    var onChange: (EqualizerSettings) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Space.lg) {
                        if !isAvailable {
                            unavailableNotice
                        }
                        enableToggle
                        bands
                        resetButton
                    }
                    .padding(Theme.Space.lg)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var unavailableNotice: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.mechanismIssue)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Not available for this song")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("The system would not let the tone control attach to this stream. Your settings are saved and will apply to the next song that accepts them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .card(Theme.Palette.surface)
    }

    private var enableToggle: some View {
        Toggle(isOn: Binding(
            get: { settings.isEnabled },
            set: { newValue in
                settings.isEnabled = newValue
                onChange(settings)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tone control")
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(settings.isEnabled ? "Shaping the backing track" : "Off — the song plays as published")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .tint(Theme.Palette.accent)
        .padding(Theme.Space.md)
        .card(Theme.Palette.surface)
    }

    private var bands: some View {
        VStack(spacing: Theme.Space.lg) {
            band(
                title: "Bass",
                caption: "100 Hz",
                value: settings.bassGainDB,
                set: { settings.setBass($0); onChange(settings) }
            )
            band(
                title: "Mid",
                caption: "1 kHz",
                value: settings.midGainDB,
                set: { settings.setMid($0); onChange(settings) }
            )
            band(
                title: "Treble",
                caption: "8 kHz",
                value: settings.trebleGainDB,
                set: { settings.setTreble($0); onChange(settings) }
            )
        }
        .padding(Theme.Space.md)
        .card(Theme.Palette.surface)
        .opacity(settings.isEnabled ? 1 : 0.45)
        .disabled(!settings.isEnabled)
    }

    private func band(
        title: String,
        caption: String,
        value: Double,
        set: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Text(Self.label(for: value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(value == 0 ? Theme.Palette.textSecondary : Theme.Palette.accent)
            }

            Slider(
                value: Binding(get: { value }, set: set),
                in: EqualizerSettings.gainRange,
                step: 0.5
            )
            .tint(Theme.Palette.accent)
        }
    }

    /// Signed, because "+3.0 dB" and "−3.0 dB" must be distinguishable at a
    /// glance in a dim room.
    static func label(for gain: Double) -> String {
        if gain == 0 { return "0 dB" }
        let sign = gain > 0 ? "+" : "−"
        return String(format: "%@%.1f dB", sign, abs(gain))
    }

    private var resetButton: some View {
        Button {
            settings.reset()
            onChange(settings)
        } label: {
            Text("Flat")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.Palette.accent)
        .disabled(settings.bassGainDB == 0 && settings.midGainDB == 0 && settings.trebleGainDB == 0)
    }
}
