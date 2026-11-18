import AVFoundation

/// Sums system audio and the microphone into one 48 kHz stereo track, the way
/// OBS mixes its sources at unity gain. Each source is placed by timestamp;
/// a source that has not delivered by the time a block is drained counts as
/// silence, so one stalled source never holds up the other.
public final class AudioMixer {
    public enum Input: Int, CaseIterable {
        case system
        case mic
    }

    private struct Track {
        var timeline: AudioTimeline
        /// Sample index of `left[0]`.
        var base: Int64 = 0
        var left: [Float] = []
        var right: [Float] = []
        var end: Int64 { base + Int64(left.count) }
    }

    public let format: AVAudioFormat
    public private(set) var mixedUntil: Int64 = 0
    private var tracks: [Track]

    public init(sampleRate: Double = 48_000) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        tracks = Input.allCases.map { _ in Track(timeline: AudioTimeline(sampleRate: sampleRate)) }
    }

    /// `buffer` must be float, at the mixer's sample rate, mono or stereo.
    /// Mono is placed in both channels.
    public func push(_ buffer: AVAudioPCMBuffer, from input: Input, mediaTime: Double) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        var track = tracks[input.rawValue]
        let start = track.timeline.place(frames: frames, mediaTime: mediaTime)
        let l = data[0]
        let r = buffer.format.channelCount > 1 ? data[1] : data[0]
        if track.left.isEmpty { track.base = max(start, mixedUntil) }
        for i in 0..<frames {
            let index = start + Int64(i)
            if index < mixedUntil || index < track.base { continue }
            let offset = Int(index - track.base)
            if offset >= track.left.count {
                let grow = offset - track.left.count + 1
                track.left.append(contentsOf: repeatElement(0, count: grow))
                track.right.append(contentsOf: repeatElement(0, count: grow))
            }
            track.left[offset] = l[i]
            track.right[offset] = r[i]
        }
        tracks[input.rawValue] = track
    }

    /// Furthest sample any source has delivered.
    public var deliveredUntil: Int64 {
        tracks.map(\.end).max() ?? mixedUntil
    }

    /// Mixes everything up to `limit` (exclusive). Returns the block and the
    /// sample index it starts at, or nil when there is nothing new.
    public func drain(upTo limit: Int64) -> (start: Int64, buffer: AVAudioPCMBuffer)? {
        guard limit > mixedUntil else { return nil }
        let count = Int(limit - mixedUntil)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        let ol = out.floatChannelData![0], or = out.floatChannelData![1]
        for i in 0..<count {
            ol[i] = 0
            or[i] = 0
        }
        for t in tracks.indices {
            var track = tracks[t]
            for i in 0..<count {
                let index = mixedUntil + Int64(i)
                let offset = Int(index - track.base)
                guard offset >= 0, offset < track.left.count else { continue }
                ol[i] += track.left[offset]
                or[i] += track.right[offset]
            }
            let consumed = Int(min(max(limit - track.base, 0), Int64(track.left.count)))
            if consumed > 0 {
                track.left.removeFirst(consumed)
                track.right.removeFirst(consumed)
                track.base += Int64(consumed)
            }
            if track.left.isEmpty { track.base = limit }
            tracks[t] = track
        }
        for i in 0..<count {
            ol[i] = min(1, max(-1, ol[i]))
            or[i] = min(1, max(-1, or[i]))
        }
        let start = mixedUntil
        mixedUntil = limit
        return (start, out)
    }

    /// After a pause both sources start a fresh run of buffers.
    public func resetTimelines() {
        for t in tracks.indices { tracks[t].timeline.reset() }
    }
}
