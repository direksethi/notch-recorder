import AVFoundation
import CoreMedia

public enum PCM {
    /// Wraps an audio CMSampleBuffer's data in an AVAudioPCMBuffer (copied).
    public static func buffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
        else { return nil }
        var streamDesc = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }

    /// Builds a CMSampleBuffer for AVAssetWriter from a PCM buffer.
    public static func sampleBuffer(from pcm: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
        var desc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: pcm.format.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &desc) == noErr,
            let desc
        else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcm.format.sampleRate)),
            presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: desc, sampleCount: CMItemCount(pcm.frameLength), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr,
            let sample
        else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            bufferList: pcm.audioBufferList) == noErr
        else { return nil }
        return sample
    }

    /// Root mean square of the first channel, 0...1.
    public static func rms(_ pcm: AVAudioPCMBuffer) -> Float {
        guard let data = pcm.floatChannelData, pcm.frameLength > 0 else { return 0 }
        let n = Int(pcm.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        return (sum / Float(n)).squareRoot()
    }
}

/// Converts any PCM format to a fixed target (used for 48 kHz float stereo
/// mixing and 16 kHz mono for speech recognition).
public final class Resampler {
    public let output: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    public init(output: AVAudioFormat) {
        self.output = output
    }

    public static func speech() -> Resampler {
        Resampler(output: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!)
    }

    public func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if input.format == output { return input }
        if converter == nil || inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: output)
            inputFormat = input.format
        }
        guard let converter else { return nil }
        let ratio = output.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { return nil }
        return out
    }

    public func samples(_ input: AVAudioPCMBuffer) -> [Float] {
        guard let out = convert(input), let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }
}
