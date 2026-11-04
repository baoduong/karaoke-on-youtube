// T059 — QualityDetailView.
//
// Reports the selected rendition's format, codec, and bitrate (FR-005).
// Surfaces `degradesQuality` so the app does not advertise quality the
// Bluetooth link discards (FR-014).
//
// Satisfies: FR-005, FR-014

import SwiftUI

// MARK: - QualityDetailView

/// Shows the selected rendition's quality details and the active route's
/// quality characteristics.
///
/// `degradesQuality` is surfaced here because Bluetooth re-encodes the decoded
/// audio before transmitting it — the app must not claim quality it cannot
/// deliver (FR-014, audio-pipeline.md Audio Quality Reality). Because a
/// Bluetooth PA speaker is the normal party setup, "Quality Degraded" is
/// presented as a calm factual note on a neutral raised surface rather than an
/// alarm.
struct QualityDetailView: View {

    let rendition: AudioRendition?
    let outputRoute: OutputRoute

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        renditionSection
                        routeSection
                    }
                    .padding(Theme.Space.lg)
                }
            }
            .navigationTitle("Audio Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Rendition section (FR-005)

    private var renditionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "Selected Rendition")

            if let rendition {
                VStack(spacing: Theme.Space.md) {
                    // Primary format, codec, and bitrate pills
                    HStack(spacing: Theme.Space.sm) {
                        metricTile(title: "Format", value: containerName(rendition.container))
                        metricTile(title: "Codec", value: codecName(rendition.codec))
                        metricTile(
                            title: "Bitrate",
                            value: rendition.averageBitrateBps.map { "\($0 / 1000) kbps" } ?? "Unknown"
                        )
                    }

                    VStack(spacing: Theme.Space.sm) {
                        detailRow(label: "Container", value: containerName(rendition.container))
                        detailRow(label: "Codec", value: codecName(rendition.codec))
                        detailRow(
                            label: "Bitrate",
                            value: rendition.averageBitrateBps.map { "\($0 / 1000) kbps" } ?? "Unknown"
                        )

                        if let sampleRate = rendition.sampleRateHz {
                            detailRow(label: "Sample Rate", value: "\(sampleRate / 1000) kHz")
                        }

                        if let channels = rendition.channelCount {
                            detailRow(label: "Channels", value: channels == 2 ? "Stereo" : "\(channels)")
                        }

                        detailRow(label: "Itag", value: "\(rendition.itag)")
                    }
                    .padding(Theme.Space.md)
                    .card(Theme.Palette.surface)
                }
            } else {
                EmptyStateView(
                    icon: "waveform",
                    title: "No rendition selected",
                    message: "Start playing a song to inspect its audio format, codec, and bitrate."
                )
                .frame(maxWidth: .infinity)
                .card(Theme.Palette.surface)
            }
        }
    }

    // MARK: Route section (FR-014)

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "Output Route")

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                detailRow(label: "Route", value: routeLabel)
                detailRow(label: "External", value: outputRoute.isExternal ? "Yes" : "No")
                detailRow(
                    label: "Output Latency",
                    value: String(format: "%.0f ms", outputRoute.outputLatencyMs)
                )

                Divider()
                    .overlay(Theme.Palette.surfaceRaised)

                if outputRoute.degradesQuality {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Image(systemName: "info.circle.fill")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.accentDim)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text("Quality Degraded")
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.textPrimary)

                            Text("This route re-encodes the audio before transmitting it. The actual quality is lower than the rendition bitrate suggests.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.md)
                    .card(Theme.Palette.surfaceRaised, radius: Theme.Radius.sm)
                } else {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.success)

                        Text("No quality degradation")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textPrimary)

                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.md)
                    .card(Theme.Palette.surfaceRaised, radius: Theme.Radius.sm)
                }
            }
            .padding(Theme.Space.md)
            .card(Theme.Palette.surface)
        }
    }

    // MARK: Building Blocks

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(value)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Palette.accent)
                .lineLimit(1)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Theme.Palette.surface)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    // MARK: Helpers

    private var routeLabel: String {
        switch outputRoute.kind {
        case .bluetoothA2DP: return "Bluetooth A2DP"
        case .builtInSpeaker: return "Built-in Speaker"
        case .wiredLineOut: return "Wired Line Out"
        case .usbAudio: return "USB Audio"
        case .airPlay: return "AirPlay"
        case .other: return "Other"
        }
    }

    private func codecName(_ codec: Codec) -> String {
        switch codec {
        case .aac: return "AAC"
        case .opus: return "Opus"
        case .vorbis: return "Vorbis"
        case .other(let s): return s
        }
    }

    private func containerName(_ container: Container) -> String {
        switch container {
        case .m4a: return "M4A"
        case .webm: return "WebM"
        case .mp4: return "MP4"
        case .other(let s): return s
        }
    }
}
