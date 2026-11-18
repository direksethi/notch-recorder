import Foundation

/// Decides what to do about free disk space while recording.
public struct DiskSpaceGuard: Sendable {
    public enum Verdict: Equatable { case fine, warn, stop }

    public var warnBelow: Int64 = 5 * 1_000_000_000
    public var stopBelow: Int64 = 1 * 1_000_000_000

    public init() {}

    public func verdict(freeBytes: Int64) -> Verdict {
        if freeBytes < stopBelow { return .stop }
        if freeBytes < warnBelow { return .warn }
        return .fine
    }

    public static func freeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}
