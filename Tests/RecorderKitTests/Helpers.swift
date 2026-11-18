import AVFoundation
import CoreVideo
@testable import RecorderKit

func grayBGRA(width: Int, height: Int, value: UInt8) -> CVPixelBuffer {
    let pb = PixelBuffers.make(width: width, height: height, format: kCVPixelFormatType_32BGRA)!
    CVPixelBufferLockBaseAddress(pb, [])
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    for y in 0..<height {
        let row = base + y * stride
        for x in 0..<width {
            row[x * 4 + 0] = value
            row[x * 4 + 1] = value
            row[x * 4 + 2] = value
            row[x * 4 + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, [])
    return pb
}

func pcm(_ samples: [Float], channels: Int = 1, rate: Double = 48_000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false)!
    let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    b.frameLength = AVAudioFrameCount(samples.count)
    for c in 0..<channels {
        for (i, s) in samples.enumerated() { b.floatChannelData![c][i] = s }
    }
    return b
}

func tempURL(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nr-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

/// Produces frames and audio like ScreenCaptureKit would, from timers.
final class FakeScreenSource: ScreenSource {
    var onVideo: ((CVPixelBuffer, Double) -> Void)?
    var onSystemAudio: ((AVAudioPCMBuffer, Double) -> Void)?
    var onMicAudio: ((AVAudioPCMBuffer, Double) -> Void)?
    var onError: ((Error) -> Void)?
    var displaySize = CGSize(width: 640, height: 270)
    var displayName = "Fake"
    var backingScale = 1.0
    var startCount = 0
    var failStart = false
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "fake.source")
    private let frame: CVPixelBuffer

    init() {
        frame = grayBGRA(width: 640, height: 270, value: 100)
    }

    func start() async throws {
        startCount += 1
        if failStart { throw CaptureError.failed("fake failure") }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(20))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = HostClock.now()
            self.onVideo?(self.frame, now)
            let tone = (0..<960).map { Float(sin(Double($0) / 10)) * 0.1 }
            self.onSystemAudio?(pcm(tone, channels: 2), now)
            self.onMicAudio?(pcm(tone, channels: 1), now)
        }
        timer = t
        t.resume()
    }

    func stop() async {
        timer?.cancel()
        timer = nil
    }

    func emitError() {
        onError?(CaptureError.failed("display disconnected"))
    }
}
