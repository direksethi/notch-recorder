import CoreMedia

/// Maps host time to media time for a constant frame rate recording, leaving
/// out any time spent paused (system sleep). Pure, so it is unit tested.
public struct FramePacer: Sendable {
    public let fps: Int32
    public private(set) var start: Double?
    private var pausedTotal: Double = 0
    private var pausedAt: Double?

    public init(fps: Int32) {
        self.fps = fps
    }

    public var isPaused: Bool { pausedAt != nil }

    public mutating func begin(at hostTime: Double) {
        start = hostTime
        pausedTotal = 0
        pausedAt = nil
    }

    public mutating func pause(at hostTime: Double) {
        guard pausedAt == nil, start != nil else { return }
        pausedAt = hostTime
    }

    public mutating func resume(at hostTime: Double) {
        guard let p = pausedAt else { return }
        pausedTotal += max(0, hostTime - p)
        pausedAt = nil
    }

    /// Seconds of recorded media at `hostTime` (frozen while paused).
    public func mediaTime(at hostTime: Double) -> Double {
        guard let start else { return 0 }
        let now = pausedAt ?? hostTime
        return max(0, now - start - pausedTotal)
    }

    public func frameIndex(at hostTime: Double) -> Int64 {
        Int64((mediaTime(at: hostTime) * Double(fps)).rounded(.down))
    }

    public func pts(for index: Int64) -> CMTime {
        CMTime(value: index, timescale: fps)
    }

    public var frameDuration: CMTime { CMTime(value: 1, timescale: fps) }
}

public enum HostClock {
    /// Current host time in seconds, the same clock ScreenCaptureKit stamps
    /// its sample buffers with.
    public static func now() -> Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }
}
