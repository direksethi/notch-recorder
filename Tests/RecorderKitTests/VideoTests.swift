import AVFoundation
import Testing
import VideoToolbox
@testable import RecorderKit

@Test func scalerProducesExpectedLumaForFlatGrey() throws {
    let scaler = try MetalScaler()
    let src = grayBGRA(width: 640, height: 270, value: 128)
    let dst = PixelBuffers.make(width: 512, height: 216, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)!
    try scaler.scale(src, into: dst)
    CVPixelBufferLockBaseAddress(dst, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(dst, .readOnly) }
    let y = CVPixelBufferGetBaseAddressOfPlane(dst, 0)!.assumingMemoryBound(to: UInt8.self)
    let c = CVPixelBufferGetBaseAddressOfPlane(dst, 1)!.assumingMemoryBound(to: UInt8.self)
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(dst, 0)
    // BT.709 video range: 16 + 219 * 128/255 = 125.9
    #expect(abs(Int(y[100 * yStride + 200]) - 126) <= 1)
    #expect(abs(Int(c[50 * CVPixelBufferGetBytesPerRowOfPlane(dst, 1) + 100]) - 128) <= 1)
}

@Test func scalerOutputIsNV12VideoRange() throws {
    let scaler = try MetalScaler()
    let black = grayBGRA(width: 64, height: 64, value: 0)
    let white = grayBGRA(width: 64, height: 64, value: 255)
    let dst = PixelBuffers.make(width: 32, height: 32, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)!
    func luma() -> Int {
        CVPixelBufferLockBaseAddress(dst, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dst, .readOnly) }
        return Int(CVPixelBufferGetBaseAddressOfPlane(dst, 0)!.assumingMemoryBound(to: UInt8.self)[0])
    }
    try scaler.scale(black, into: dst)
    #expect(luma() == 16)
    try scaler.scale(white, into: dst)
    #expect(luma() == 235)
}

@Test func encoderSessionHasObsProperties() throws {
    let enc = try VideoEncoder(width: 4096, height: 1728, settings: RecordingSettings())
    #expect((enc.property(kVTCompressionPropertyKey_Quality) as? NSNumber)?.floatValue == 0.6)
    #expect((enc.property(kVTCompressionPropertyKey_MaxKeyFrameInterval) as? NSNumber)?.intValue == 60)
    #expect((enc.property(kVTCompressionPropertyKey_AllowFrameReordering) as? Bool) == true)
    #expect((enc.property(kVTCompressionPropertyKey_RealTime) as? Bool) == false)
    #expect((enc.property(kVTCompressionPropertyKey_ProfileLevel) as? String) == (kVTProfileLevel_HEVC_Main_AutoLevel as String))
    #expect((enc.property(kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder) as? Bool) == true)
}

@Test func writerProducesPlayableMp4WithHevcAndAacAndRemovesWorkingMov() async throws {
    let url = tempURL("w.mp4")
    let settings = RecordingSettings()
    let enc = try VideoEncoder(width: 512, height: 216, settings: settings)
    let writer = MovieWriter(url: url, settings: settings)
    let scaler = try MetalScaler()
    let lock = NSLock()
    enc.onEncoded = { sample in
        lock.lock(); defer { lock.unlock() }
        if !writer.isStarted { try? writer.start(videoFormat: CMSampleBufferGetFormatDescription(sample)!) }
        writer.appendVideo(sample)
    }
    let src = grayBGRA(width: 640, height: 270, value: 90)
    for i in 0..<90 {
        let out = enc.makeBuffer()!
        try scaler.scale(src, into: out)
        enc.encode(out, pts: CMTime(value: Int64(i), timescale: 30), duration: CMTime(value: 1, timescale: 30))
    }
    enc.flush()
    for block in 0..<30 {
        lock.lock()
        writer.appendAudio(pcm([Float](repeating: 0.05, count: 4800), channels: 2), startSample: Int64(block * 4800))
        lock.unlock()
    }
    try await writer.finish()
    let asset = AVURLAsset(url: url)
    let video = try await asset.loadTracks(withMediaType: .video)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    #expect(video.count == 1)
    #expect(audio.count == 1)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 3) < 0.2)
    let format = try await video[0].load(.formatDescriptions)[0]
    #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC)
    #expect(!FileManager.default.fileExists(atPath: writer.workingURL.path))
}

@Test func writerAbandonedMidwayLeavesReadableFragments() async throws {
    let url = tempURL("crash.mp4")
    let settings = RecordingSettings()
    let enc = try VideoEncoder(width: 256, height: 108, settings: settings)
    let writer = MovieWriter(url: url, settings: settings)
    let scaler = try MetalScaler()
    let lock = NSLock()
    enc.onEncoded = { sample in
        lock.lock(); defer { lock.unlock() }
        if !writer.isStarted { try? writer.start(videoFormat: CMSampleBufferGetFormatDescription(sample)!) }
        writer.appendVideo(sample)
    }
    let src = grayBGRA(width: 320, height: 135, value: 50)
    for i in 0..<240 {
        let out = enc.makeBuffer()!
        try scaler.scale(src, into: out)
        enc.encode(out, pts: CMTime(value: Int64(i), timescale: 30), duration: CMTime(value: 1, timescale: 30))
        // The real recorder always writes audio (silence when nothing plays);
        // AVAssetWriter only cuts fragments once both tracks have data.
        lock.lock()
        writer.appendAudio(pcm([Float](repeating: 0, count: 1600), channels: 2), startSample: Int64(i * 1600))
        lock.unlock()
        if i % 30 == 0 { try await Task.sleep(for: .milliseconds(300)) }
    }
    enc.flush()
    try await Task.sleep(for: .milliseconds(500))
    // Simulate a crash: never finish the file.
    writer.abandon()
    let asset = AVURLAsset(url: writer.workingURL)
    let duration = try await asset.load(.duration).seconds
    #expect(duration > 1)
}

@Test func sidecarCompressesToM4a() async throws {
    let url = tempURL("mic.caf")
    let s = try SidecarWriter(url: url)
    s.append([Float](repeating: 0.1, count: 16_000))
    s.padTo(sample: 32_000)
    #expect(s.length == 32_000)
    s.close()
    let m4a = try await SidecarWriter.compress(url)
    #expect(m4a.pathExtension == "m4a")
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let file = try AVAudioFile(forReading: m4a)
    #expect(abs(Int(file.length) - 32_000) < 2048)
}
