import Common
import Foundation

/// Speech recognition and voice activity detection. FluidSpeechEngine is the
/// real one; tests use fakes.
public protocol SpeechEngine: Sendable {
    func load() async throws
    func unload() async
    /// Probability (0...1) that a 4096-sample (256 ms, 16 kHz) chunk is speech.
    func vadProbability(_ chunk: [Float], source: AudioSource) async throws -> Float
    /// Text for one utterance of 16 kHz mono audio.
    func transcribe(_ samples: [Float], source: AudioSource) async throws -> (text: String, confidence: Double)
}

/// A finished piece of transcript, before it is stored.
public struct SegmentDraft: Sendable, Equatable {
    public var source: AudioSource
    public var startMs: Int64
    public var endMs: Int64
    public var text: String
    public var confidence: Double

    public init(source: AudioSource, startMs: Int64, endMs: Int64, text: String, confidence: Double) {
        self.source = source
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.confidence = confidence
    }
}

public enum TranscriptError: Error, LocalizedError, Equatable {
    case modelUnavailable(String)
    case audioUnreadable(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let m): "The speech model could not be loaded: \(m)"
        case .audioUnreadable(let m): "The recording's audio could not be read: \(m)"
        case .cancelled: "Transcription was cancelled."
        }
    }
}

enum Samples {
    static let rate: Int64 = 16_000
    static func ms(_ sample: Int64) -> Int64 { sample * 1000 / rate }
}
