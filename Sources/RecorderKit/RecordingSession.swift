import AVFoundation
import Common
import CoreMedia

/// One recording, from start to a finalised file. Owns capture, scaling,
/// encoding, audio mixing, the MP4 writer and the per-source sidecars.
///
/// Threading: every piece of mutable pipeline state lives on `queue`.
/// `start`, `stop`, `pause` and `resume` hop onto it as needed.
public final class RecordingSession: @unchecked Sendable {
    public struct Paths: Sendable {
        public var video: URL
        public var micAudio: URL
        public var systemAudio: URL

        public init(video: URL, micAudio: URL, systemAudio: URL) {
            self.video = video
            self.micAudio = micAudio
            self.systemAudio = systemAudio
        }
    }

    public let id: String
    public let settings: RecordingSettings
    public let paths: Paths
    public let events: AsyncStream<RecordingEvent>
    public private(set) var startedAt = Date()

    private let continuation: AsyncStream<RecordingEvent>.Continuation
    private let source: ScreenSource
    private let queue = DispatchQueue(label: "recorder.pipeline", qos: .userInteractive)
    private let videoQueue = DispatchQueue(label: "recorder.video", qos: .userInteractive)
    private let freeBytes: () -> Int64
    private let diskGuard = DiskSpaceGuard()
    private let makeScaler: () throws -> MetalScaler?

    // Pipeline state (on `queue`).
    private var state: SessionState = .idle
    private var pacer: FramePacer
    private var scaler: MetalScaler?
    private var encoder: VideoEncoder?
    private let writer: MovieWriter
    private let mixer: AudioMixer
    private let micTo48k: Resampler
    private let systemTo48k: Resampler
    private let micToSpeech = Resampler.speech()
    private let systemToSpeech = Resampler.speech()
    private var micSpeechTimeline = AudioTimeline(sampleRate: 16_000)
    private var systemSpeechTimeline = AudioTimeline(sampleRate: 16_000)
    private var micSidecar: SidecarWriter?
    private var systemSidecar: SidecarWriter?
    private var latestFrame: CVPixelBuffer?
    private var lastFrameIndex: Int64 = -1
    private var ticker: DispatchSourceTimer?
    private var tickerSuspended = false
    private var tickCount = 0
    private var micLevel: Float = 0
    private var systemLevel: Float = 0
    private var restarts: [Double] = []
    private var warnedDisk = false
    private var outputSize: CGSize = .zero
    private var fatal: RecorderError?

    /// Audio is written this far behind real time so late buffers still land.
    private let audioLatency: Double = 0.2

    public init(
        id: String,
        settings: RecordingSettings,
        paths: Paths,
        source: ScreenSource,
        freeBytes: (() -> Int64)? = nil,
        makeScaler: @escaping () throws -> MetalScaler? = { try MetalScaler() }
    ) {
        self.id = id
        self.settings = settings
        self.paths = paths
        self.source = source
        self.makeScaler = makeScaler
        let videoFolder = paths.video.deletingLastPathComponent()
        self.freeBytes = freeBytes ?? { DiskSpaceGuard.freeBytes(at: videoFolder) }
        pacer = FramePacer(fps: settings.fps)
        writer = MovieWriter(url: paths.video, settings: settings)
        mixer = AudioMixer(sampleRate: settings.sampleRate)
        micTo48k = Resampler(output: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: settings.sampleRate, channels: 1, interleaved: false)!)
        systemTo48k = Resampler(output: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: settings.sampleRate, channels: 2, interleaved: false)!)
        (events, continuation) = AsyncStream.makeStream(of: RecordingEvent.self, bufferingPolicy: .bufferingNewest(256))
    }

    public var currentState: SessionState { queue.sync { state } }

    // MARK: Lifecycle

    public func start() async throws {
        try queue.sync {
            guard case .idle = state else { throw RecorderError.alreadyRecording }
            setState(.starting)
        }
        do {
            try FileManager.default.createDirectory(at: paths.video.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.micAudio.deletingLastPathComponent(), withIntermediateDirectories: true)
            micSidecar = try SidecarWriter(url: paths.micAudio)
            systemSidecar = try SidecarWriter(url: paths.systemAudio)
            scaler = try makeScaler()
            wireSource()
            try await source.start()
            let size = settings.outputSize(for: source.displaySize, backingScale: source.backingScale)
            let enc = try VideoEncoder(width: Int(size.width), height: Int(size.height), settings: settings)
            enc.onEncoded = { [weak self] sample in self?.queue.async { self?.handleEncoded(sample) } }
            enc.onError = { [weak self] error in self?.queue.async { self?.fail(RecorderError.from(error)) } }
            queue.sync {
                outputSize = size
                encoder = enc
                startedAt = Date()
                pacer.begin(at: HostClock.now())
                startTicker()
                setState(.recording)
            }
            Log.recorder.info("recording \(self.id, privacy: .public) at \(Int(size.width))x\(Int(size.height))")
        } catch {
            await source.stop()
            micSidecar?.close()
            systemSidecar?.close()
            let e = RecorderError.from(error)
            queue.sync { setState(.failed(e, nil)) }
            continuation.finish()
            throw e
        }
    }

    /// Stops and finalises the file. Returns nil if nothing was recorded.
    @discardableResult
    public func stop() async -> RecordingOutput? {
        let proceed: Bool = queue.sync {
            switch state {
            case .recording, .paused:
                setState(.stopping)
                return true
            default:
                return false
            }
        }
        guard proceed else { return nil }
        return await finalize(error: nil)
    }

    /// Pauses capture (used when the Mac goes to sleep). Time spent paused is
    /// left out of the recording.
    public func pause() async {
        let proceed: Bool = queue.sync {
            guard case .recording = state else { return false }
            pacer.pause(at: HostClock.now())
            if !tickerSuspended {
                ticker?.suspend()
                tickerSuspended = true
            }
            setState(.paused)
            return true
        }
        guard proceed else { return }
        await source.stop()
    }

    public func resume() async {
        guard case .paused = currentState else { return }
        do {
            try await source.start()
            queue.sync {
                pacer.resume(at: HostClock.now())
                mixer.resetTimelines()
                micSpeechTimeline.reset()
                systemSpeechTimeline.reset()
                if tickerSuspended {
                    ticker?.resume()
                    tickerSuspended = false
                }
                setState(.recording)
            }
        } catch {
            queue.async { self.fail(RecorderError.from(error)) }
        }
    }

    // MARK: Source wiring

    private func wireSource() {
        source.onVideo = { [weak self] pb, _ in self?.handleFrame(pb) }
        source.onSystemAudio = { [weak self] pcm, t in self?.queue.async { self?.handleAudio(pcm, hostTime: t, mic: false) } }
        source.onMicAudio = { [weak self] pcm, t in self?.queue.async { self?.handleAudio(pcm, hostTime: t, mic: true) } }
        source.onError = { [weak self] error in self?.queue.async { self?.handleStreamError(error) } }
    }

    /// Scales each new screen frame into an encoder buffer straight away;
    /// the ticker encodes the latest one at a constant frame rate.
    private func handleFrame(_ pb: CVPixelBuffer) {
        videoQueue.async { [weak self] in
            guard let self else { return }
            let encoder = self.queue.sync { self.encoder }
            guard let encoder, let out = encoder.makeBuffer() else { return }
            do {
                if let scaler = self.scaler {
                    try scaler.scale(pb, into: out)
                } else {
                    return
                }
                self.queue.async { self.latestFrame = out }
            } catch {
                self.queue.async { self.fail(RecorderError.from(error)) }
            }
        }
    }

    private func handleAudio(_ pcm: AVAudioPCMBuffer, hostTime: Double, mic: Bool) {
        guard case .recording = state else { return }
        let mediaTime = pacer.mediaTime(at: hostTime)
        if let mixed = (mic ? micTo48k : systemTo48k).convert(pcm) {
            mixer.push(mixed, from: mic ? .mic : .system, mediaTime: mediaTime)
            if mic { micLevel = max(micLevel * 0.6, PCM.rms(mixed)) } else { systemLevel = max(systemLevel * 0.6, PCM.rms(mixed)) }
        }
        let speech = (mic ? micToSpeech : systemToSpeech).samples(pcm)
        guard !speech.isEmpty else { return }
        let start: Int64
        if mic {
            start = micSpeechTimeline.place(frames: speech.count, mediaTime: mediaTime)
            micSidecar?.padTo(sample: start)
            micSidecar?.append(speech)
        } else {
            start = systemSpeechTimeline.place(frames: speech.count, mediaTime: mediaTime)
            systemSidecar?.padTo(sample: start)
            systemSidecar?.append(speech)
        }
        continuation.yield(.speech(source: mic ? .me : .others, samples: speech, startSample: start))
    }

    private func handleEncoded(_ sample: CMSampleBuffer) {
        if !writer.isStarted, let format = CMSampleBufferGetFormatDescription(sample) {
            do {
                try writer.start(videoFormat: format)
            } catch {
                fail(RecorderError.from(error))
                return
            }
        }
        writer.appendVideo(sample)
        if let error = writer.error { fail(RecorderError.from(error)) }
    }

    // MARK: Ticker (constant frame rate, audio drain, levels, disk)

    private func startTicker() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = 1.0 / Double(settings.fps)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        ticker = t
        t.resume()
    }

    private func tick() {
        guard case .recording = state else { return }
        let now = HostClock.now()
        let index = pacer.frameIndex(at: now)
        if let frame = latestFrame, let encoder, index > lastFrameIndex {
            // Fill every frame slot so the file is constant frame rate, but
            // never try to catch up more than a second after a stall.
            let first = max(lastFrameIndex + 1, index - Int64(settings.fps))
            for i in first...index {
                encoder.encode(frame, pts: pacer.pts(for: i), duration: pacer.frameDuration)
            }
            lastFrameIndex = index
        }
        let limit = Int64(((pacer.mediaTime(at: now) - audioLatency) * settings.sampleRate).rounded(.down))
        drainAudio(upTo: limit)

        tickCount += 1
        if tickCount % 3 == 0 {
            continuation.yield(.levels(me: micLevel, others: systemLevel))
            micLevel *= 0.5
            systemLevel *= 0.5
        }
        if tickCount % Int(settings.fps) == 0 {
            continuation.yield(.elapsed(pacer.mediaTime(at: now)))
        }
        if tickCount % (Int(settings.fps) * 10) == 1 {
            checkDisk()
        }
    }

    private func drainAudio(upTo limit: Int64) {
        guard let (start, block) = mixer.drain(upTo: limit) else { return }
        writer.appendAudio(block, startSample: start)
    }

    private func checkDisk() {
        switch diskGuard.verdict(freeBytes: freeBytes()) {
        case .fine:
            break
        case .warn:
            if !warnedDisk {
                warnedDisk = true
                continuation.yield(.warning("Less than 5 GB of disk space left. Recording stops automatically below 1 GB."))
            }
        case .stop:
            fail(.diskFull)
        }
    }

    // MARK: Errors

    private func handleStreamError(_ error: Error) {
        guard case .recording = state else { return }
        let now = HostClock.now()
        restarts = restarts.filter { now - $0 < 5 } + [now]
        if restarts.count > 3 {
            fail(RecorderError.from(error))
            return
        }
        continuation.yield(.warning("Screen capture was interrupted. Reconnecting…"))
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            do {
                try await self.source.start()
                Log.recorder.info("capture restarted")
            } catch {
                self.queue.async { self.fail(RecorderError.from(error)) }
            }
        }
    }

    /// Stops the recording because of an error, keeping whatever was written.
    private func fail(_ error: RecorderError) {
        switch state {
        case .recording, .paused:
            Log.recorder.error("recording failed: \(error.localizedDescription, privacy: .public)")
            fatal = error
            setState(.stopping)
            Task { [weak self] in _ = await self?.finalize(error: error) }
        default:
            break
        }
    }

    private func finalize(error: RecorderError?) async -> RecordingOutput? {
        await source.stop()
        let enc: VideoEncoder? = queue.sync {
            // A suspended dispatch source must be resumed before it is released.
            if tickerSuspended {
                ticker?.resume()
                tickerSuspended = false
            }
            ticker?.cancel()
            ticker = nil
            // Encode the final frame slot so the file runs to the stop time.
            let now = HostClock.now()
            let index = pacer.frameIndex(at: now)
            if let frame = latestFrame, let encoder, index > lastFrameIndex {
                encoder.encode(frame, pts: pacer.pts(for: index), duration: pacer.frameDuration)
                lastFrameIndex = index
            }
            return encoder
        }
        enc?.flush()
        let duration: TimeInterval = queue.sync {
            drainAudio(upTo: max(mixer.deliveredUntil, mixer.mixedUntil))
            return Double(lastFrameIndex + 1) / Double(settings.fps)
        }
        var finalError = error
        do {
            let wrote = try await writer.finish()
            if !wrote && finalError == nil { finalError = .captureFailed("No frames were captured.") }
        } catch {
            finalError = finalError ?? RecorderError.from(error)
        }
        micSidecar?.close()
        systemSidecar?.close()
        scaler?.flush()

        let size = (try? paths.video.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let output = size > 0
            ? RecordingOutput(
                id: id, videoURL: paths.video,
                micAudioURL: FileManager.default.fileExists(atPath: paths.micAudio.path) ? paths.micAudio : nil,
                systemAudioURL: FileManager.default.fileExists(atPath: paths.systemAudio.path) ? paths.systemAudio : nil,
                startedAt: startedAt, duration: max(0, duration),
                width: Int(outputSize.width), height: Int(outputSize.height),
                displayName: source.displayName, sizeBytes: size)
            : nil
        queue.sync {
            encoder = nil
            latestFrame = nil
            if let finalError {
                setState(.failed(finalError, output))
            } else if let output {
                setState(.finished(output))
            }
        }
        continuation.finish()
        Log.recorder.info("recording \(self.id, privacy: .public) finalised, \(size) bytes, dropped video \(self.writer.droppedVideo)")
        return output
    }

    private func setState(_ new: SessionState) {
        state = new
        continuation.yield(.state(new))
    }
}
