import Common
import Foundation

public enum RecorderError: Error, LocalizedError, Equatable {
    case permissionDenied
    case noDisplay
    case alreadyRecording
    case captureFailed(String)
    case encoderFailed(String)
    case writerFailed(String)
    case diskFull

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: CaptureError.permissionDenied.errorDescription
        case .noDisplay: CaptureError.noDisplay.errorDescription
        case .alreadyRecording: "A recording is already in progress."
        case .captureFailed(let m): "Screen capture stopped: \(m)"
        case .encoderFailed(let m): "The video encoder failed: \(m)"
        case .writerFailed(let m): "Writing the video file failed: \(m)"
        case .diskFull: "Disk space is low. The recording was stopped and kept."
        }
    }

    static func from(_ error: Error) -> RecorderError {
        switch error {
        case let e as RecorderError: e
        case CaptureError.permissionDenied: .permissionDenied
        case CaptureError.noDisplay: .noDisplay
        case let e as EncoderError: .encoderFailed(e.localizedDescription)
        case let e as WriterError: .writerFailed(e.localizedDescription)
        case let e as ScalerError: .encoderFailed(e.localizedDescription)
        default: .captureFailed(error.localizedDescription)
        }
    }
}

public struct RecordingOutput: Sendable, Equatable {
    public var id: String
    public var videoURL: URL
    public var micAudioURL: URL?
    public var systemAudioURL: URL?
    public var startedAt: Date
    public var duration: TimeInterval
    public var width: Int
    public var height: Int
    public var displayName: String
    public var sizeBytes: Int64
}

public enum SessionState: Sendable, Equatable {
    case idle
    case starting
    case recording
    case paused
    case stopping
    case finished(RecordingOutput)
    case failed(RecorderError, RecordingOutput?)
}

public enum RecordingEvent: Sendable {
    case state(SessionState)
    case levels(me: Float, others: Float)
    case elapsed(TimeInterval)
    case warning(String)
    /// 16 kHz mono speech audio; `startSample` is on the recording's 16 kHz timeline.
    case speech(source: AudioSource, samples: [Float], startSample: Int64)
}
