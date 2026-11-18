import AppKit
import AVFoundation
import Common
import ScreenCaptureKit

/// A source of screen frames, system audio and mic audio. The real one wraps
/// ScreenCaptureKit; tests use a fake.
public protocol ScreenSource: AnyObject {
    var onVideo: ((CVPixelBuffer, Double) -> Void)? { get set }
    var onSystemAudio: ((AVAudioPCMBuffer, Double) -> Void)? { get set }
    var onMicAudio: ((AVAudioPCMBuffer, Double) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    /// Pixel size of the captured display, known once `start` returns.
    var displaySize: CGSize { get }
    var displayName: String { get }
    /// 2 for Retina displays, 1 otherwise.
    var backingScale: Double { get }
    func start() async throws
    func stop() async
}

public enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplay
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Screen recording permission is off. Turn on Notch Recorder in System Settings, Privacy & Security, Screen & System Audio Recording."
        case .noDisplay: "The display to record is not connected."
        case .failed(let m): "Screen capture failed: \(m)"
        }
    }
}

/// ScreenCaptureKit display capture configured the way OBS configures its
/// macOS Screen Capture source, plus the microphone through the same stream
/// so both share one clock.
public final class CaptureSource: NSObject, ScreenSource, SCStreamOutput, SCStreamDelegate {
    public var onVideo: ((CVPixelBuffer, Double) -> Void)?
    public var onSystemAudio: ((AVAudioPCMBuffer, Double) -> Void)?
    public var onMicAudio: ((AVAudioPCMBuffer, Double) -> Void)?
    public var onError: ((Error) -> Void)?
    public private(set) var displaySize: CGSize = .zero
    public private(set) var displayName: String = ""
    public private(set) var backingScale: Double = 1

    private let settings: RecordingSettings
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "capture.audio", qos: .userInteractive)

    public init(settings: RecordingSettings) {
        self.settings = settings
    }

    public func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Self.isPermissionError(error) ? CaptureError.permissionDenied : CaptureError.failed(error.localizedDescription)
        }
        let wanted = settings.displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == wanted })
            ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first
        else { throw CaptureError.noDisplay }

        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let pixelSize = Self.pixelSize(of: display.displayID) ?? CGSize(width: display.width, height: display.height)
        displaySize = pixelSize
        displayName = Self.name(of: display.displayID)
        backingScale = Self.backingScale(of: display.displayID, pixelWidth: pixelSize.width)

        let config = SCStreamConfiguration()
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // WindowServer converts the display's P3 to sRGB, the same result as
        // OBS's DrawD65P3 conversion before its 709 encode.
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = settings.showCursor
        config.queueDepth = 4
        config.minimumFrameInterval = CMTime(value: 9, timescale: 10 * settings.fps)
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(settings.sampleRate)
        config.channelCount = 2
        config.captureMicrophone = settings.captureMicrophone
        if settings.captureMicrophone, let mic = settings.micDeviceID ?? AVCaptureDevice.default(for: .audio)?.uniqueID {
            config.microphoneCaptureDeviceID = mic
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
        do {
            try await stream.startCapture()
        } catch {
            throw Self.isPermissionError(error) ? CaptureError.permissionDenied : CaptureError.failed(error.localizedDescription)
        }
        self.stream = stream
        Log.recorder.info("capture started \(Int(pixelSize.width))x\(Int(pixelSize.height)) on \(self.displayName, privacy: .public)")
    }

    public func stop() async {
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            Log.recorder.info("stopCapture: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sample.isValid else { return }
        let hostTime = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete,
                  let pb = CMSampleBufferGetImageBuffer(sample)
            else { return }
            onVideo?(pb, hostTime)
        case .audio:
            if let pcm = PCM.buffer(from: sample) { onSystemAudio?(pcm, hostTime) }
        case .microphone:
            if let pcm = PCM.buffer(from: sample) { onMicAudio?(pcm, hostTime) }
        @unknown default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.recorder.error("stream stopped: \(error.localizedDescription, privacy: .public)")
        self.stream = nil
        onError?(CaptureError.failed(error.localizedDescription))
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.userDeclined.rawValue
    }

    static func pixelSize(of id: CGDirectDisplayID) -> CGSize? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }

    /// Pixels per point of the display's current mode (2 on Retina).
    static func backingScale(of id: CGDirectDisplayID, pixelWidth: CGFloat) -> Double {
        guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return 1 }
        return Double(pixelWidth) / Double(mode.width)
    }

    static func name(of id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Display \(id)"
    }
}
