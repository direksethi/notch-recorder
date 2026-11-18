import AVFoundation
import Common

public enum WriterError: Error, LocalizedError {
    case cannotCreate(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreate(let m): "Could not create the video file: \(m)"
        case .failed(let m): "Writing the video file failed: \(m)"
        }
    }
}

/// Writes already-encoded HEVC frames plus AAC audio. While recording the
/// file is a QuickTime movie with movie fragments every 2 s (`workingURL`),
/// so a crash loses at most the last fragment. `finish()` rewraps it,
/// without re-encoding, into the final MP4 at `url`.
public final class MovieWriter {
    /// The final .mp4.
    public let url: URL
    /// The fragmented .mov written while recording.
    public let workingURL: URL
    private let settings: RecordingSettings
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pendingAudio: [CMSampleBuffer] = []
    public private(set) var droppedVideo = 0

    public init(url: URL, settings: RecordingSettings) {
        self.url = url
        self.workingURL = Self.workingURL(for: url)
        self.settings = settings
    }

    public static func workingURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("mov")
    }

    public var isStarted: Bool { writer != nil }

    /// Starts the file once the first encoded frame gives us its format.
    public func start(videoFormat: CMFormatDescription) throws {
        guard writer == nil else { return }
        try? FileManager.default.removeItem(at: workingURL)
        let w: AVAssetWriter
        do {
            w = try AVAssetWriter(outputURL: workingURL, fileType: .mov)
        } catch {
            throw WriterError.cannotCreate(error.localizedDescription)
        }
        w.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        video.expectsMediaDataInRealTime = true
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: settings.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: settings.audioBitrate,
        ])
        audio.expectsMediaDataInRealTime = true
        guard w.canAdd(video), w.canAdd(audio) else { throw WriterError.cannotCreate("inputs rejected") }
        w.add(video)
        w.add(audio)
        guard w.startWriting() else {
            throw WriterError.cannotCreate(w.error?.localizedDescription ?? "startWriting failed")
        }
        w.startSession(atSourceTime: .zero)
        writer = w
        videoInput = video
        audioInput = audio
        for s in pendingAudio where audio.isReadyForMoreMediaData { _ = audio.append(s) }
        pendingAudio.removeAll()
    }

    public var error: Error? {
        guard let w = writer, w.status == .failed else { return nil }
        return WriterError.failed(w.error?.localizedDescription ?? "unknown")
    }

    public func appendVideo(_ sample: CMSampleBuffer) {
        guard let input = videoInput else { return }
        if input.isReadyForMoreMediaData {
            if !input.append(sample) { Log.recorder.error("video append failed: \(String(describing: self.writer?.error))") }
        } else {
            droppedVideo += 1
        }
    }

    /// `pcm` is 48 kHz float stereo starting at `startSample`.
    public func appendAudio(_ pcm: AVAudioPCMBuffer, startSample: Int64) {
        let pts = CMTime(value: startSample, timescale: CMTimeScale(settings.sampleRate))
        guard let sample = PCM.sampleBuffer(from: pcm, pts: pts) else { return }
        guard let input = audioInput else {
            if pendingAudio.count < 500 { pendingAudio.append(sample) }
            return
        }
        if input.isReadyForMoreMediaData {
            _ = input.append(sample)
        }
    }

    /// Finalises the movie and rewraps it as the MP4 at `url`. Returns false
    /// when nothing was written.
    @discardableResult
    public func finish() async throws -> Bool {
        guard let w = writer else { return false }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await w.finishWriting()
        writer = nil
        if w.status == .failed {
            throw WriterError.failed(w.error?.localizedDescription ?? "unknown")
        }
        try await Remux.toMP4(from: workingURL, to: url)
        return true
    }

    /// Stops without finalising (used by tests to simulate a crash).
    public func abandon() {
        writer = nil
        videoInput = nil
        audioInput = nil
    }
}

/// Rewraps a movie as MP4 without re-encoding.
public enum Remux {
    public static func toMP4(from source: URL, to destination: URL, deleteSource: Bool = true) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw WriterError.failed("cannot create export session")
        }
        do {
            try await export.export(to: destination, as: .mp4)
        } catch {
            throw WriterError.failed("could not finish the MP4: \(error.localizedDescription)")
        }
        if deleteSource { try? FileManager.default.removeItem(at: source) }
    }
}
