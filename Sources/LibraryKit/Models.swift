import Common
import Foundation
import GRDB

public enum RecordingStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case recording, unsaved, saved, discarded, failed
}

public enum TranscriptStatus: String, Codable, Sendable, DatabaseValueConvertible {
    /// Transcription turned off or nothing transcribed yet.
    case none
    /// Being transcribed live while recording.
    case live
    case complete
    /// Stopped early (crash, quit); can be finished with re-transcribe.
    case partial
    case failed
    case retranscribing
}

public struct RecordingRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recording"

    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMs: Int64
    public var displayName: String
    public var width: Int
    public var height: Int
    /// Where the video sits until it is saved.
    public var stagingPath: String?
    /// Where the video was saved to.
    public var videoPath: String?
    public var sizeBytes: Int64
    public var status: RecordingStatus
    public var transcriptStatus: TranscriptStatus
    /// Everything before this offset has final segments.
    public var transcribedUntilMs: Int64
    public var micAudioPath: String?
    public var systemAudioPath: String?
    public var thumbnailCount: Int
    /// Exactly how the file was made (RecordingSettings as JSON).
    public var settingsJSON: String
    public var errorMessage: String?

    public init(
        id: String, title: String, startedAt: Date, endedAt: Date? = nil, durationMs: Int64 = 0,
        displayName: String = "", width: Int = 0, height: Int = 0, stagingPath: String? = nil,
        videoPath: String? = nil, sizeBytes: Int64 = 0, status: RecordingStatus = .recording,
        transcriptStatus: TranscriptStatus = .none, transcribedUntilMs: Int64 = 0,
        micAudioPath: String? = nil, systemAudioPath: String? = nil, thumbnailCount: Int = 0,
        settingsJSON: String = "{}", errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.displayName = displayName
        self.width = width
        self.height = height
        self.stagingPath = stagingPath
        self.videoPath = videoPath
        self.sizeBytes = sizeBytes
        self.status = status
        self.transcriptStatus = transcriptStatus
        self.transcribedUntilMs = transcribedUntilMs
        self.micAudioPath = micAudioPath
        self.systemAudioPath = systemAudioPath
        self.thumbnailCount = thumbnailCount
        self.settingsJSON = settingsJSON
        self.errorMessage = errorMessage
    }

    /// The file to play: the saved copy, else the staged one.
    public var currentVideoPath: String? { videoPath ?? stagingPath }
}

public struct SegmentRow: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "segment"

    public var id: Int64?
    public var recordingId: String
    public var source: AudioSource
    public var startMs: Int64
    public var endMs: Int64
    public var text: String
    /// Set the first time a segment is edited, so the original is kept.
    public var originalText: String?
    public var confidence: Double

    public init(
        id: Int64? = nil, recordingId: String, source: AudioSource, startMs: Int64, endMs: Int64,
        text: String, originalText: String? = nil, confidence: Double = 1
    ) {
        self.id = id
        self.recordingId = recordingId
        self.source = source
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.originalText = originalText
        self.confidence = confidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension AudioSource: DatabaseValueConvertible {}

public struct RecordingSummary: Codable, Sendable, Equatable {
    public var recording: RecordingRow
    public var preview: String?
    public var previewSource: AudioSource?
    public var segmentCount: Int
    public var fileMissing: Bool

    public init(recording: RecordingRow, preview: String?, previewSource: AudioSource?, segmentCount: Int, fileMissing: Bool) {
        self.recording = recording
        self.preview = preview
        self.previewSource = previewSource
        self.segmentCount = segmentCount
        self.fileMissing = fileMissing
    }
}

public struct SearchHit: Codable, Sendable, Equatable {
    public var recordingId: String
    public var recordingTitle: String
    public var startedAt: Date
    public var durationMs: Int64
    public var segmentId: Int64
    public var source: AudioSource
    public var startMs: Int64
    /// Segment text with matches wrapped in U+0001 ... U+0002.
    public var highlighted: String
}
