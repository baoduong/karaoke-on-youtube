import AVFoundation

/// Three-band tone control spliced into `AVPlayer`'s audio (FR-043).
///
/// ## Real-time safety (Constitution Principle I)
///
/// `process` runs on the audio render thread. What it does, and why each is
/// safe:
///
/// - `MTAudioProcessingTapGetSourceAudio` — the API provided for this purpose.
/// - `engine.manualRenderingBlock` — Apple's render entry point, documented
///   for `.realtime` mode, which is the mode used here.
/// - `memcpy` — no allocation, no locking.
/// - Property reads on a `final class` through `takeUnretainedValue()` — a
///   direct call with no dynamic dispatch and no retain.
///
/// What it deliberately does not do: allocate, lock, log, or touch Swift
/// collections. Every buffer it needs is allocated in `prepare`.
///
/// Band gains are **not** passed through this callback. They are set on
/// `AVAudioUnitEQ` from the main thread, because AudioUnit parameters are
/// built to be set from any thread and the unit ramps them internally. That
/// is most of the reason for using `AVAudioUnitEQ` rather than hand-written
/// biquads: the lock-free parameter path already exists and is Apple's.
final class EqualizerTap {

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)

    private var sourceNode: AVAudioSourceNode?
    private var renderBuffer: AVAudioPCMBuffer?

    /// Set at the top of each `process` so the source node's render block can
    /// find the audio the tap just handed us. Written and read on the same
    /// thread within one callback.
    private var pendingSource: UnsafeMutablePointer<AudioBufferList>?
    private var pendingFrames: AVAudioFrameCount = 0

    private var isRunning = false

    init() {
        configureBands(.flat)
    }

    // MARK: Parameters

    /// Apply new gains. Safe from the main thread while audio is rendering.
    func apply(_ settings: EqualizerSettings) {
        configureBands(settings)
    }

    private func configureBands(_ settings: EqualizerSettings) {
        let bands = eq.bands
        guard bands.count >= 3 else { return }

        bands[0].filterType = .lowShelf
        bands[0].frequency = EqualizerSettings.bassFrequency
        bands[0].gain = Float(settings.bassGainDB)
        bands[0].bypass = false

        bands[1].filterType = .parametric
        bands[1].frequency = EqualizerSettings.midFrequency
        bands[1].bandwidth = 1.0
        bands[1].gain = Float(settings.midGainDB)
        bands[1].bypass = false

        bands[2].filterType = .highShelf
        bands[2].frequency = EqualizerSettings.trebleFrequency
        bands[2].gain = Float(settings.trebleGainDB)
        bands[2].bypass = false

        eq.globalGain = Float(settings.headroomGainDB)
        eq.bypass = !settings.isEnabled
    }

    // MARK: Tap construction

    /// Builds the tap. Returns nil when the platform refuses to create one,
    /// which the caller must treat as "no EQ on this item" rather than as a
    /// playback failure.
    ///
    /// `forTrackMix` picks the creation function, and it is not optional.
    /// `AVAudioMix.h` is explicit: when `trackID` is
    /// `AVAudioMixInputParametersTrackMixID`, a tap made with plain
    /// `MTAudioProcessingTapCreate` has an *undefined* processing format.
    /// Only the preferred-format variant is valid there.
    func makeProcessingTap(forTrackMix: Bool) -> MTAudioProcessingTap? {
        // Retained on purpose, released in `tapFinalize`. The tap outlives the
        // player item that carries it, and an unretained pointer here means
        // the callbacks dereference freed memory during teardown — which is
        // a crash, observed, not a theory.
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tap: MTAudioProcessingTap?
        let flags = MTAudioProcessingTapCreationFlags(kMTAudioProcessingTapCreationFlag_PreEffects)

        if forTrackMix {
            guard #available(iOS 27.0, *), let format = Self.preferredFormat() else { return nil }
            let status = MTAudioProcessingTapCreateWithPreferredFormat(
                kCFAllocatorDefault, &callbacks, flags, format, &tap
            )
            guard status == noErr else { return nil }
        } else {
            let status = MTAudioProcessingTapCreate(
                kCFAllocatorDefault, &callbacks, flags, &tap
            )
            guard status == noErr else { return nil }
        }
        return tap
    }

    /// Deinterleaved 32-bit float stereo — what `AVAudioEngine` wants, so the
    /// tap and the engine agree and no conversion is needed on the render
    /// thread. The prepare callback still reads back the format actually
    /// granted, because the header warns it may differ.
    private static func preferredFormat() -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat
                | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        )
        return status == noErr ? description : nil
    }

    // MARK: Lifecycle, called from the tap callbacks

    fileprivate func prepare(maxFrames: CMItemCount, processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
        guard let format = AVAudioFormat(streamDescription: processingFormat) else { return }

        let frameCapacity = AVAudioFrameCount(maxFrames)
        renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self, let source = self.pendingSource else {
                return noErr
            }
            Self.copy(from: source, to: audioBufferList, frames: frameCount)
            return noErr
        }
        sourceNode = node

        engine.attach(node)
        engine.attach(eq)
        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        do {
            try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: frameCapacity)
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
            DiagnosticLog.recordEnvironmentError(
                .offline,
                songID: "equalizer",
                providerID: SourceProviderID(rawValue: "EqualizerTap.prepare")
            )
        }
    }

    fileprivate func unprepare() {
        isRunning = false
        engine.stop()
        engine.disableManualRenderingMode()
        if let node = sourceNode {
            engine.detach(node)
        }
        engine.detach(eq)
        sourceNode = nil
        renderBuffer = nil
        pendingSource = nil
    }

    fileprivate func process(
        tap: MTAudioProcessingTap,
        numberFrames: CMItemCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        framesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferList,
            flagsOut,
            nil,
            framesOut
        )
        guard status == noErr else { return }

        // Not running, or nothing to do: the source audio is already in
        // bufferList, so leaving it untouched is the correct pass-through.
        guard isRunning, !eq.bypass, let output = renderBuffer else { return }

        let frames = AVAudioFrameCount(framesOut.pointee)
        guard frames > 0, frames <= output.frameCapacity else { return }

        pendingSource = bufferList
        pendingFrames = frames
        defer { pendingSource = nil }

        output.frameLength = frames
        var error: OSStatus = noErr
        let result = engine.manualRenderingBlock(frames, output.mutableAudioBufferList, &error)

        guard result == .success, error == noErr else { return }
        Self.copy(from: output.mutableAudioBufferList, to: bufferList, frames: frames)
    }

    /// Frame-for-frame copy between two buffer lists of the same layout.
    private static func copy(
        from source: UnsafeMutablePointer<AudioBufferList>,
        to destination: UnsafeMutablePointer<AudioBufferList>,
        frames: AVAudioFrameCount
    ) {
        let src = UnsafeMutableAudioBufferListPointer(source)
        let dst = UnsafeMutableAudioBufferListPointer(destination)
        let count = min(src.count, dst.count)
        for index in 0..<count {
            guard let from = src[index].mData, let into = dst[index].mData else { continue }
            let bytes = min(src[index].mDataByteSize, dst[index].mDataByteSize)
            memcpy(into, from, Int(bytes))
        }
        _ = frames
    }
}

// MARK: - C callbacks

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

/// Balances the retain taken in `makeProcessingTap`. This is the only place
/// the tap's hold on its owner is given up.
private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    guard let storage = MTAudioProcessingTapGetStorage(tap) as UnsafeMutableRawPointer? else { return }
    Unmanaged<EqualizerTap>.fromOpaque(storage).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, format in
    guard let storage = MTAudioProcessingTapGetStorage(tap) as UnsafeMutableRawPointer? else { return }
    Unmanaged<EqualizerTap>.fromOpaque(storage)
        .takeUnretainedValue()
        .prepare(maxFrames: maxFrames, processingFormat: format)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    guard let storage = MTAudioProcessingTapGetStorage(tap) as UnsafeMutableRawPointer? else { return }
    Unmanaged<EqualizerTap>.fromOpaque(storage)
        .takeUnretainedValue()
        .unprepare()
}

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    guard let storage = MTAudioProcessingTapGetStorage(tap) as UnsafeMutableRawPointer? else { return }
    Unmanaged<EqualizerTap>.fromOpaque(storage)
        .takeUnretainedValue()
        .process(
            tap: tap,
            numberFrames: numberFrames,
            bufferList: bufferListInOut,
            framesOut: numberFramesOut,
            flagsOut: flagsOut
        )
}
