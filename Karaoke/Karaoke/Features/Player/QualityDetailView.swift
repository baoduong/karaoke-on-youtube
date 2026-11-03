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
/// deliver (FR-014, audio-pipeline.md Audio Quality Reality).
struct QualityDetailView: View {

    let rendition: AudioRendition?
    let outputRoute: OutputRoute

    var body: some View {
        NavigationStack {
            List {
                renditionSection
                routeSection
            }
            .navigationTitle("Audio Quality")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Rendition section (FR-005)

    private var renditionSection: some View {
        Section("Selected Rendition") {
            if let rendition {
                LabeledContent("Codec", value: codecName(rendition.codec))
                LabeledContent("Container", value: containerName(rendition.container))

                if let bps = rendition.averageBitrateBps {
                    LabeledContent("Bitrate", value: "\(bps / 1000) kbps")
                } else {
                    LabeledContent("Bitrate", value: "Unknown")
                }

                if let sampleRate = rendition.sampleRateHz {
                    LabeledContent("Sample Rate", value: "\(sampleRate / 1000) kHz")
                }

                if let channels = rendition.channelCount {
                    LabeledContent("Channels", value: channels == 2 ? "Stereo" : "\(channels)")
                }

                LabeledContent("Itag", value: "\(rendition.itag)")
            } else {
                Text("No rendition selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Route section (FR-014)

    private var routeSection: some View {
        Section("Output Route") {
            LabeledContent("Route", value: routeLabel)

            LabeledContent("External", value: outputRoute.isExternal ? "Yes" : "No")

            LabeledContent("Output Latency") {
                Text(String(format: "%.0f ms", outputRoute.outputLatencyMs))
                    .foregroundStyle(outputRoute.outputLatencyMs > 100 ? .orange : .primary)
            }

            if outputRoute.degradesQuality {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quality Degraded")
                            .font(.body)
                        Text("This route re-encodes the audio before transmitting it. The actual quality is lower than the rendition bitrate suggests.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No quality degradation")
                        .font(.body)
                }
            }
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
