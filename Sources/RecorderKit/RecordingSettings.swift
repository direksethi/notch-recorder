import CoreGraphics
import Foundation

/// How a recording is made. The defaults follow a common OBS profile for
/// Apple's hardware HEVC encoder (see docs/architecture.md).
public struct RecordingSettings: Codable, Sendable, Equatable {
    public var displayID: UInt32?
    public var micDeviceID: String?
    /// Off when microphone permission is denied; the recording then has
    /// system audio only.
    public var captureMicrophone = true
    public var showCursor: Bool = true
    /// Output size as a fraction of the display's pixel size. 0.8 turns
    /// 5120x2160 into 4096x1728.
    public var scale: Double = 0.8
    /// Retina displays (a MacBook's built-in screen) are recorded at this many
    /// output pixels per screen point: 4/3 keeps text crisp while the file
    /// stays light. A 14" MacBook Pro (3024x1964 pixels, 1512x982 points)
    /// becomes 2016x1308.
    public var retinaPointScale: Double = 4.0 / 3.0
    public var fps: Int32 = 30
    /// VideoToolbox constant quality (OBS "CRF" 60 maps to 0.60).
    public var quality: Double = 0.60
    public var keyframeSeconds: Int = 2
    public var audioBitrate: Int = 160_000
    public var sampleRate: Double = 48_000

    public init() {}

    /// Fraction of the display's pixels to record. `backingScale` is 1 for
    /// regular displays (such as a 5120x2160 monitor) and 2 for Retina.
    public func scaleFactor(backingScale: Double) -> Double {
        backingScale > 1.01 ? min(1, retinaPointScale / backingScale) : scale
    }

    /// Even dimensions (HEVC 4:2:0 needs them), scaled from the display's
    /// pixel size.
    public func outputSize(for display: CGSize, backingScale: Double = 1) -> CGSize {
        func even(_ v: Double) -> Double { max(2, (v / 2).rounded(.down) * 2) }
        let f = scaleFactor(backingScale: backingScale)
        return CGSize(width: even(display.width * f), height: even(display.height * f))
    }

    public var keyframeInterval: Int { keyframeSeconds * Int(fps) }
}
