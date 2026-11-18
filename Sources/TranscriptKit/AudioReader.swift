import AVFoundation
import Foundation

/// Decodes any audio file (CAF, M4A, or the audio track of an MP4/MOV) to
/// 16 kHz mono float, in chunks, so hours of audio never sit in memory.
public enum AudioReader {
    public static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// Calls `body` with consecutive chunks; return false from it to stop.
    public static func read16kMono(
        _ url: URL, from startSeconds: Double = 0, body: ([Float]) async throws -> Bool
    ) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptError.audioUnreadable("no audio track in \(url.lastPathComponent)")
        }
        let reader = try AVAssetReader(asset: asset)
        if startSeconds > 0 {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: startSeconds, preferredTimescale: 16_000), duration: .positiveInfinity)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw TranscriptError.audioUnreadable("cannot decode \(url.lastPathComponent)") }
        reader.add(output)
        guard reader.startReading() else {
            throw TranscriptError.audioUnreadable(reader.error?.localizedDescription ?? "cannot read")
        }
        defer { reader.cancelReading() }
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / 4)
            floats.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            if try await !body(floats) { return }
        }
        if reader.status == .failed {
            throw TranscriptError.audioUnreadable(reader.error?.localizedDescription ?? "read failed")
        }
    }
}
