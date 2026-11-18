import Common
import Foundation

public enum TranscriberStatus: Sendable, Equatable {
    case loading
    case running
    /// Transcription stopped; the recording itself carries on.
    case failed(String)
    case finished
}

/// Transcribes the mic and system audio of a recording as it happens.
/// Failures never reach the recorder: they switch this to `.failed` and the
/// audio is dropped (it is still in the sidecar files for later).
public actor LiveTranscriber {
    public typealias PartialHandler = @Sendable (AudioSource, String) -> Void
    public typealias FinalHandler = @Sendable (SegmentDraft) -> Void
    public typealias StatusHandler = @Sendable (TranscriberStatus) -> Void

    private struct Stream {
        var segmenter: UtteranceSegmenter
        var pending: [Float] = []
        var pendingStart: Int64 = 0
        var utterance = 0
        var partialInFlight = false
    }

    private let engine: SpeechEngine
    private let onPartial: PartialHandler
    private let onFinal: FinalHandler
    private let onStatus: StatusHandler
    private let deduper = EchoDeduper()
    private var streams: [AudioSource: Stream] = [:]
    private var status: TranscriberStatus = .loading
    private var consecutiveFailures = 0
    private var heldMine: [SegmentDraft] = []
    private var recentOthers: [SegmentDraft] = []
    /// Audio that arrived while the models were loading (first ever load
    /// compiles them for about a minute); processed once they are ready.
    private var backlog: [(AudioSource, [Float], Int64)] = []
    private var backlogSamples = 0
    private let backlogLimit = 16_000 * 60 * 10

    public init(
        engine: SpeechEngine, partials: Bool = true,
        onPartial: @escaping PartialHandler, onFinal: @escaping FinalHandler, onStatus: @escaping StatusHandler
    ) {
        self.engine = engine
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onStatus = onStatus
        for s in [AudioSource.me, .others] {
            streams[s] = Stream(segmenter: UtteranceSegmenter(partials: partials))
        }
    }

    /// Loads the models. Audio fed before this finishes is buffered by the
    /// segmenter's caller (the recorder keeps it in the sidecars anyway).
    public func start() async {
        setStatus(.loading)
        do {
            try await engine.load()
            setStatus(.running)
            let queued = backlog
            backlog = []
            backlogSamples = 0
            for (source, samples, start) in queued {
                await feed(source: source, samples: samples, startSample: start)
            }
        } catch {
            Log.transcript.error("model load failed: \(error.localizedDescription, privacy: .public)")
            setStatus(.failed(TranscriptError.modelUnavailable(error.localizedDescription).localizedDescription))
        }
    }

    public var currentStatus: TranscriberStatus { status }

    /// 16 kHz mono samples for `source`, starting at `startSample` on the
    /// recording's timeline.
    public func feed(source: AudioSource, samples: [Float], startSample: Int64) async {
        if status == .loading {
            if backlogSamples < backlogLimit {
                backlog.append((source, samples, startSample))
                backlogSamples += samples.count
            }
            return
        }
        guard status == .running, var stream = streams[source] else { return }
        if stream.pending.isEmpty { stream.pendingStart = startSample }
        stream.pending += samples
        var chunks: [([Float], Int64)] = []
        while stream.pending.count >= 4096 {
            chunks.append((Array(stream.pending.prefix(4096)), stream.pendingStart))
            stream.pending.removeFirst(4096)
            stream.pendingStart += 4096
        }
        streams[source] = stream
        for (chunk, start) in chunks {
            await process(chunk: chunk, start: start, source: source)
        }
        releaseHeld(force: false)
    }

    /// Flushes utterances in progress and commits everything.
    public func finish() async {
        if status == .running {
            for source in [AudioSource.me, .others] {
                guard var stream = streams[source] else { continue }
                let outputs = stream.segmenter.flush()
                stream.utterance += 1
                streams[source] = stream
                for o in outputs { await handle(o, source: source) }
            }
        }
        releaseHeld(force: true)
        await engine.unload()
        if case .failed = status { return }
        setStatus(.finished)
    }

    private func process(chunk: [Float], start: Int64, source: AudioSource) async {
        let p: Float
        do {
            p = try await engine.vadProbability(chunk, source: source)
        } catch {
            noteFailure(error)
            return
        }
        guard var stream = streams[source] else { return }
        let outputs = stream.segmenter.push(chunk, startSample: start, probability: p)
        streams[source] = stream
        for o in outputs { await handle(o, source: source) }
    }

    private func handle(_ output: UtteranceSegmenter.Output, source: AudioSource) async {
        switch output {
        case .partial(let samples, _):
            guard var stream = streams[source], !stream.partialInFlight else { return }
            stream.partialInFlight = true
            let utterance = stream.utterance
            streams[source] = stream
            let result = try? await engine.transcribe(samples, source: source)
            streams[source]?.partialInFlight = false
            // Drop a partial that arrives after its utterance was finalised.
            if let result, streams[source]?.utterance == utterance, !result.text.isEmpty {
                onPartial(source, result.text)
            }
        case .final(let samples, let startSample, let endSample):
            streams[source]?.utterance += 1
            do {
                let result = try await engine.transcribe(samples, source: source)
                consecutiveFailures = 0
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                onPartial(source, "")
                guard !text.isEmpty else { return }
                let draft = SegmentDraft(
                    source: source, startMs: Samples.ms(startSample), endMs: Samples.ms(endSample),
                    text: text, confidence: result.confidence)
                commit(draft)
            } catch {
                noteFailure(error)
            }
        }
    }

    /// "Me" segments wait briefly so a matching "Others" segment (the echo
    /// source) can arrive first.
    private func commit(_ draft: SegmentDraft) {
        if draft.source == .me {
            heldMine.append(draft)
        } else {
            recentOthers.append(draft)
            recentOthers.removeAll { $0.endMs < draft.endMs - 30_000 }
            onFinal(draft)
        }
    }

    private func releaseHeld(force: Bool) {
        let latestOthers = recentOthers.map(\.endMs).max() ?? 0
        let latestTimeline = streams.values.map(\.pendingStart).max().map(Samples.ms) ?? 0
        var keep: [SegmentDraft] = []
        for mine in heldMine {
            let settled = force || latestTimeline - mine.endMs > 2_000 || latestOthers > mine.endMs + 1_500
            guard settled else {
                keep.append(mine)
                continue
            }
            if deduper.shouldDrop(me: mine, others: recentOthers) {
                Log.transcript.info("dropped echoed segment")
            } else {
                onFinal(mine)
            }
        }
        heldMine = keep
    }

    private func noteFailure(_ error: Error) {
        consecutiveFailures += 1
        Log.transcript.error("transcription error: \(error.localizedDescription, privacy: .public)")
        if consecutiveFailures >= 3 {
            setStatus(.failed("Live transcription stopped after repeated errors. Use Transcribe again after saving."))
        }
    }

    private func setStatus(_ s: TranscriberStatus) {
        status = s
        onStatus(s)
    }
}
