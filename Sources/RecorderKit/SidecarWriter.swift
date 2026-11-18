import AVFoundation
import Common

/// Keeps one source's audio (mic or system) as 16 kHz mono so a recording can
/// be transcribed again later with "Me" and "Others" intact. Written as
/// 16-bit PCM in CAF while recording (survives a crash), compressed to AAC
/// in an .m4a once the recording is saved.
public final class SidecarWriter {
    public let url: URL
    private var file: AVAudioFile?
    public static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    public init(url: URL) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false)
    }

    /// Appends 16 kHz mono float samples.
    public func append(_ samples: [Float]) {
        guard let file, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        do {
            try file.write(from: buffer)
        } catch {
            Log.recorder.error("sidecar write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pads with silence up to `sample` so the sidecar stays aligned with the
    /// video after a gap (pause, dropout).
    public func padTo(sample: Int64) {
        guard let file else { return }
        let missing = sample - file.length
        guard missing > 0 else { return }
        var remaining = missing
        while remaining > 0 {
            let n = Int(min(remaining, 16_000))
            append([Float](repeating: 0, count: n))
            remaining -= Int64(n)
        }
    }

    public var length: Int64 { file?.length ?? 0 }

    public func close() {
        file = nil
    }

    /// Converts a CAF sidecar to AAC 32 kbit/s .m4a and deletes the CAF.
    public static func compress(_ caf: URL) async throws -> URL {
        let out = caf.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: out)
        let input = try AVAudioFile(forReading: caf, commonFormat: .pcmFormatFloat32, interleaved: false)
        let output = try AVAudioFile(
            forWriting: out,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false)
        let chunk: AVAudioFrameCount = 16_000 * 10
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: chunk) else {
            throw WriterError.failed("no buffer")
        }
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        try FileManager.default.removeItem(at: caf)
        return out
    }
}
