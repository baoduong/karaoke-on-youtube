import AVFoundation
import SwiftUI

/// Reports what the audio session says about the active output route, and emits
/// a click paired with a full-screen flash so the gap between them can be read
/// off a video recording.
///
/// The flash is the whole point: the session reports the latency it *believes*
/// the route has, and third-party Bluetooth speakers frequently misreport it.
/// Filming the screen and the room together turns that belief into a number.
@MainActor
@Observable
final class ProbeModel {

    var routeDescription = "—"
    var portType = "—"
    var reportedLatencyMs: Double = 0
    var sampleRate: Double = 0
    var ioBufferMs: Double = 0
    var channels: Int = 0
    var isFlashing = false
    var clickCount = 0
    var log: [String] = []

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    func start() {
        configureSession()
        buildClick()
        refreshRoute()
        observeRouteChanges()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
        } catch {
            log.append("session error: \(error.localizedDescription)")
        }
    }

    private func buildClick() {
        let session = AVAudioSession.sharedInstance()
        let rate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }

        let frames = AVAudioFrameCount(rate * 0.05)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames

        // A short burst with an instantaneous attack. A slow fade-in would blur
        // the very edge the video measurement depends on.
        for channel in 0..<Int(format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) {
                let progress = Double(frame) / Double(frames)
                let envelope = Float(pow(1.0 - progress, 3.0))
                let tone = Float(sin(2.0 * .pi * 2_000.0 * Double(frame) / rate))
                samples[frame] = tone * envelope * 0.8
            }
        }
        clickBuffer = buffer

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            log.append("engine error: \(error.localizedDescription)")
        }
    }

    func refreshRoute() {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.first

        routeDescription = output?.portName ?? "none"
        portType = output?.portType.rawValue ?? "none"
        reportedLatencyMs = session.outputLatency * 1000
        sampleRate = session.sampleRate
        ioBufferMs = session.ioBufferDuration * 1000
        channels = session.outputNumberOfChannels
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshRoute()
                self?.log.append("route changed -> \(self?.portType ?? "?")")
            }
        }
    }

    func startClicks() {
        stopClicks()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireClick() }
        }
        fireClick()
    }

    func stopClicks() {
        timer?.invalidate()
        timer = nil
    }

    private func fireClick() {
        guard let clickBuffer else { return }
        clickCount += 1

        // Flash and audio are dispatched in the same turn. Whatever gap the
        // camera records between them is the route's real output delay.
        isFlashing = true
        player.scheduleBuffer(clickBuffer, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            isFlashing = false
        }
    }
}

struct ProbeView: View {
    @State private var model = ProbeModel()

    var body: some View {
        ZStack {
            (model.isFlashing ? Color.white : Color.black)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Route Probe")
                    .font(.largeTitle.bold())

                Group {
                    row("Route", model.routeDescription)
                    row("Port type", model.portType)
                    row("Reported latency", String(format: "%.1f ms", model.reportedLatencyMs))
                    row("Sample rate", String(format: "%.0f Hz", model.sampleRate))
                    row("IO buffer", String(format: "%.2f ms", model.ioBufferMs))
                    row("Output channels", "\(model.channels)")
                    row("Clicks fired", "\(model.clickCount)")
                }
                .font(.system(.body, design: .monospaced))

                HStack(spacing: 12) {
                    Button("Refresh") { model.refreshRoute() }
                        .buttonStyle(.borderedProminent)
                    Button("Start clicks") { model.startClicks() }
                        .buttonStyle(.borderedProminent)
                    Button("Stop") { model.stopClicks() }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 8)

                if !model.log.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.log.suffix(6), id: \.self) { line in
                            Text(line).font(.caption.monospaced())
                        }
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(24)
            .foregroundStyle(model.isFlashing ? .black : .white)
        }
        .task { model.start() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).opacity(0.6)
            Spacer()
            Text(value).bold()
        }
    }
}
