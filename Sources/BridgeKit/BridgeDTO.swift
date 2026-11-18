import Common
import Foundation
import LibraryKit

// Wire shapes for the bridge. Each mirrors a Schema in
// web/packages/core/src/contract.ts; BridgeKitTests decode the fixtures that
// file's tests write, so a mismatch fails the build.

public struct RecordingSummaryDTO: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var startedAt: Double
    public var durationMs: Int64
    public var sizeBytes: Int64
    public var width: Int
    public var height: Int
    public var displayName: String
    public var status: String
    public var transcriptStatus: String
    public var transcribedUntilMs: Int64
    public var thumbnailCount: Int
    public var segmentCount: Int
    public var fileMissing: Bool
    public var hasSourceAudio: Bool
    public var preview: String?
    public var previewSource: String?
    public var videoPath: String?
    public var errorMessage: String?

    public init(_ s: RecordingSummary) {
        let r = s.recording
        id = r.id
        title = r.title
        startedAt = (r.startedAt.timeIntervalSince1970 * 1000).rounded()
        durationMs = r.durationMs
        sizeBytes = r.sizeBytes
        width = r.width
        height = r.height
        displayName = r.displayName
        status = r.status.rawValue
        transcriptStatus = r.transcriptStatus.rawValue
        transcribedUntilMs = r.transcribedUntilMs
        thumbnailCount = r.thumbnailCount
        segmentCount = s.segmentCount
        fileMissing = s.fileMissing
        hasSourceAudio = r.micAudioPath != nil || r.systemAudioPath != nil
        preview = s.preview
        previewSource = s.previewSource?.rawValue
        videoPath = r.currentVideoPath
        errorMessage = r.errorMessage
    }
}

public struct SegmentDTO: Codable, Sendable, Equatable {
    public var id: Int64
    public var source: String
    public var startMs: Int64
    public var endMs: Int64
    public var text: String
    public var originalText: String?
    public var confidence: Double

    public init(_ s: SegmentRow) {
        id = s.id ?? 0
        source = s.source.rawValue
        startMs = s.startMs
        endMs = s.endMs
        text = s.text
        originalText = s.originalText
        confidence = s.confidence
    }
}

public struct RecordingDetailDTO: Codable, Sendable, Equatable {
    public var recording: RecordingSummaryDTO
    public var segments: [SegmentDTO]

    public init(recording: RecordingSummaryDTO, segments: [SegmentDTO]) {
        self.recording = recording
        self.segments = segments
    }
}

public struct SearchHitDTO: Codable, Sendable, Equatable {
    public var recordingId: String
    public var recordingTitle: String
    public var startedAt: Double
    public var durationMs: Int64
    public var segmentId: Int64
    public var source: String
    public var startMs: Int64
    public var highlighted: String

    public init(_ h: SearchHit) {
        recordingId = h.recordingId
        recordingTitle = h.recordingTitle
        startedAt = (h.startedAt.timeIntervalSince1970 * 1000).rounded()
        durationMs = h.durationMs
        segmentId = h.segmentId
        source = h.source.rawValue
        startMs = h.startMs
        highlighted = h.highlighted
    }
}

public struct RecorderStateDTO: Codable, Sendable, Equatable {
    public var phase: String
    public var recordingId: String?
    public var startedAt: Double?

    public init(phase: String, recordingId: String? = nil, startedAt: Double? = nil) {
        self.phase = phase
        self.recordingId = recordingId
        self.startedAt = startedAt
    }
}

public struct DisplayDTO: Codable, Sendable, Equatable {
    public var id: UInt32
    public var name: String
    public var width: Int
    public var height: Int
    public var isMain: Bool
    public init(id: UInt32, name: String, width: Int, height: Int, isMain: Bool) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.isMain = isMain
    }
}

public struct MicrophoneDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var isDefault: Bool
    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public struct DevicesDTO: Codable, Sendable, Equatable {
    public var displays: [DisplayDTO]
    public var microphones: [MicrophoneDTO]
    public init(displays: [DisplayDTO], microphones: [MicrophoneDTO]) {
        self.displays = displays
        self.microphones = microphones
    }
}

public struct PermissionsDTO: Codable, Sendable, Equatable {
    public var screen: Bool
    public var microphone: Bool
    public init(screen: Bool, microphone: Bool) {
        self.screen = screen
        self.microphone = microphone
    }
}

/// Events pushed to the page (`window.__nrEvent`).
public enum BridgeEvent: Sendable {
    case recorderStateChanged(RecorderStateDTO)
    case libraryChanged(recordingId: String?)
    case retranscribeProgress(recordingId: String, fraction: Double)
    case segmentAdded(recordingId: String, segment: SegmentDTO)
    case notice(level: String, message: String)
}

extension BridgeEvent: Encodable {
    private enum Keys: String, CodingKey {
        case _tag, state, recordingId, fraction, segment, level, message
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .recorderStateChanged(let state):
            try c.encode("RecorderStateChanged", forKey: ._tag)
            try c.encode(state, forKey: .state)
        case .libraryChanged(let id):
            try c.encode("LibraryChanged", forKey: ._tag)
            try c.encodeIfPresent(id, forKey: .recordingId)
        case .retranscribeProgress(let id, let fraction):
            try c.encode("RetranscribeProgress", forKey: ._tag)
            try c.encode(id, forKey: .recordingId)
            try c.encode(fraction, forKey: .fraction)
        case .segmentAdded(let id, let segment):
            try c.encode("SegmentAdded", forKey: ._tag)
            try c.encode(id, forKey: .recordingId)
            try c.encode(segment, forKey: .segment)
        case .notice(let level, let message):
            try c.encode("Notice", forKey: ._tag)
            try c.encode(level, forKey: .level)
            try c.encode(message, forKey: .message)
        }
    }
}

/// A failure reported to the page as `{ ok: false, error }`.
public struct BridgeFailure: Error, Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        case NotFound, FileMissing, PermissionDenied, InvalidParams, Busy, Cancelled, Failed
    }

    public var code: Code
    public var message: String
    public var detail: String?

    public init(_ code: Code, _ message: String, detail: String? = nil) {
        self.code = code
        self.message = message
        self.detail = detail
    }

    public static func from(_ error: Error) -> BridgeFailure {
        switch error {
        case let f as BridgeFailure: f
        case LibraryError.notFound: BridgeFailure(.NotFound, "This recording no longer exists.")
        case is DecodingError: BridgeFailure(.InvalidParams, "Invalid request.", detail: String(describing: error))
        default: BridgeFailure(.Failed, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
