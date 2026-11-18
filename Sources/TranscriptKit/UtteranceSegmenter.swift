/// Cuts a stream of 256 ms chunks into utterances using voice activity, the
/// way FluidVoice does: speech starts at p >= 0.5, ends after 600 ms below
/// 0.35, keeps 200+ ms of lead-in, and is cut at 14 s (the model's window).
/// While someone talks it asks for a partial transcript every second.
public struct UtteranceSegmenter: Sendable {
    public enum Output: Sendable, Equatable {
        case partial(samples: [Float], startSample: Int64)
        case final(samples: [Float], startSample: Int64, endSample: Int64)
    }

    public var onThreshold: Float = 0.5
    public var offThreshold: Float = 0.35
    public var endSilence: Int = 9_600       // 600 ms
    public var keepTrailing: Int = 3_200     // 200 ms of silence kept after speech
    public var maxLength: Int = 224_000      // 14 s
    public var partialEvery: Int = 16_000    // 1 s
    public var minLength: Int = 4_800        // 300 ms of audio
    public var partials: Bool

    private var speaking = false
    private var buffer: [Float] = []
    private var start: Int64 = 0
    private var silence = 0
    private var sinceLastPartial = 0
    private var preRoll: [Float] = []
    private var preRollStart: Int64 = 0

    public init(partials: Bool = true) {
        self.partials = partials
    }

    public var isSpeaking: Bool { speaking }

    public mutating func push(_ chunk: [Float], startSample: Int64, probability: Float) -> [Output] {
        var out: [Output] = []
        if !speaking {
            if probability >= onThreshold {
                speaking = true
                buffer = preRoll + chunk
                start = preRoll.isEmpty ? startSample : preRollStart
                silence = 0
                sinceLastPartial = chunk.count
            } else {
                preRoll = chunk
                preRollStart = startSample
            }
            return out
        }

        buffer += chunk
        sinceLastPartial += chunk.count
        silence = probability < offThreshold ? silence + chunk.count : 0

        if silence >= endSilence {
            let keep = buffer.count - max(0, silence - keepTrailing)
            if let f = finalOutput(count: keep) { out.append(f) }
            reset(nextPreRoll: chunk, at: startSample)
        } else if buffer.count >= maxLength {
            if let f = finalOutput(count: buffer.count) { out.append(f) }
            // Keep listening: the next utterance starts right here.
            start += Int64(buffer.count)
            buffer = []
            sinceLastPartial = 0
        } else if partials, sinceLastPartial >= partialEvery {
            sinceLastPartial = 0
            out.append(.partial(samples: buffer, startSample: start))
        }
        return out
    }

    /// Ends any utterance in progress (recording stopped).
    public mutating func flush() -> [Output] {
        guard speaking else { return [] }
        let keep = buffer.count - max(0, silence - keepTrailing)
        let f = finalOutput(count: keep)
        reset(nextPreRoll: [], at: 0)
        return f.map { [$0] } ?? []
    }

    private func finalOutput(count: Int) -> Output? {
        guard count >= minLength else { return nil }
        return .final(samples: Array(buffer.prefix(count)), startSample: start, endSample: start + Int64(count))
    }

    private mutating func reset(nextPreRoll: [Float], at sample: Int64) {
        speaking = false
        buffer = []
        silence = 0
        sinceLastPartial = 0
        preRoll = nextPreRoll
        preRollStart = sample
    }
}
