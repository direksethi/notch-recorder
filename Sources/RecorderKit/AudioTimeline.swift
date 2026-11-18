/// Places a source's buffers on the recording's sample timeline. Buffers stay
/// back to back while their timestamps agree with that within 10 ms, so
/// normal jitter never causes clicks; past that (clock drift, a dropout) the
/// source is re-anchored to its timestamp. This keeps a USB mic and system
/// audio in sync over hours.
public struct AudioTimeline: Sendable {
    public let sampleRate: Double
    public let tolerance: Int64
    public private(set) var next: Int64?

    public init(sampleRate: Double, toleranceSeconds: Double = 0.010) {
        self.sampleRate = sampleRate
        self.tolerance = Int64(sampleRate * toleranceSeconds)
    }

    /// Returns the sample index where this buffer starts.
    public mutating func place(frames: Int, mediaTime: Double) -> Int64 {
        let ideal = Int64((mediaTime * sampleRate).rounded())
        let start: Int64
        if let n = next, abs(ideal - n) <= tolerance {
            start = n
        } else {
            start = ideal
        }
        next = start + Int64(frames)
        return start
    }

    public mutating func reset() {
        next = nil
    }
}
