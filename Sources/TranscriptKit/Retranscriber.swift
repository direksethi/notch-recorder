import Common
import Foundation

/// Transcribes a saved recording again from its audio: the per-source
/// sidecars when present (keeps Me and Others), otherwise the video's mixed
/// track (labelled Speaker). Resumable from any offset; cancellable.
public struct Retranscriber: Sendable {
    public struct Input: Sendable {
        public var micAudio: URL?
        public var systemAudio: URL?
        public var video: URL?
        public var fromMs: Int64
        public var durationMs: Int64

        public init(micAudio: URL?, systemAudio: URL?, video: URL?, fromMs: Int64, durationMs: Int64) {
            self.micAudio = micAudio
            self.systemAudio = systemAudio
            self.video = video
            self.fromMs = fromMs
            self.durationMs = durationMs
        }
    }

    private let engine: SpeechEngine

    public init(engine: SpeechEngine) {
        self.engine = engine
    }

    /// Returns segments sorted by start time. `progress` gets 0...1.
    public func run(_ input: Input, progress: @Sendable (Double) -> Void) async throws -> [SegmentDraft] {
        var sources: [(AudioSource, URL)] = []
        let fm = FileManager.default
        if let mic = input.micAudio, fm.fileExists(atPath: mic.path) { sources.append((.me, mic)) }
        if let sys = input.systemAudio, fm.fileExists(atPath: sys.path) { sources.append((.others, sys)) }
        if sources.isEmpty, let video = input.video, fm.fileExists(atPath: video.path) { sources.append((.speaker, video)) }
        guard !sources.isEmpty else { throw TranscriptError.audioUnreadable("no audio files found for this recording") }

        try await engine.load()
        defer { Task { await engine.unload() } }

        let totalMs = max(1, input.durationMs - input.fromMs) * Int64(sources.count)
        var doneMs: Int64 = 0
        var drafts: [SegmentDraft] = []
        let fromSample = input.fromMs * 16

        for (source, url) in sources {
            var segmenter = UtteranceSegmenter(partials: false)
            var pending: [Float] = []
            var position = fromSample
            let finals = { (outputs: [UtteranceSegmenter.Output]) async throws -> Void in
                for case let .final(samples, start, end) in outputs {
                    let r = try await engine.transcribe(samples, source: source)
                    let text = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        drafts.append(SegmentDraft(source: source, startMs: Samples.ms(start), endMs: Samples.ms(end), text: text, confidence: r.confidence))
                    }
                }
            }
            try await AudioReader.read16kMono(url, from: Double(input.fromMs) / 1000) { floats in
                try Task.checkCancellation()
                pending += floats
                while pending.count >= 4096 {
                    let chunk = Array(pending.prefix(4096))
                    pending.removeFirst(4096)
                    let p = try await engine.vadProbability(chunk, source: source)
                    try await finals(segmenter.push(chunk, startSample: position, probability: p))
                    position += 4096
                }
                progress(Double(doneMs + Samples.ms(position - fromSample)) / Double(totalMs))
                return true
            }
            try await finals(segmenter.flush())
            doneMs += Samples.ms(position - fromSample)
        }
        progress(1)
        return drafts.sorted { ($0.startMs, $0.source.rawValue) < ($1.startMs, $1.source.rawValue) }
    }
}
