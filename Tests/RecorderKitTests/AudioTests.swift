import AVFoundation
import Testing
@testable import RecorderKit

@Test func contiguousBuffersStayContiguous() {
    var t = AudioTimeline(sampleRate: 48_000)
    #expect(t.place(frames: 480, mediaTime: 0) == 0)
    // 2 ms of jitter: stays back to back.
    #expect(t.place(frames: 480, mediaTime: 0.012) == 480)
}

@Test func driftOver10msReanchors() {
    var t = AudioTimeline(sampleRate: 48_000)
    _ = t.place(frames: 480, mediaTime: 0)
    #expect(t.place(frames: 480, mediaTime: 0.1) == 4800)
}

@Test func micMonoIsDuplicatedToBothChannels() {
    let m = AudioMixer()
    m.push(pcm([0.5, 0.5, 0.5, 0.5], channels: 1), from: .mic, mediaTime: 0)
    let (start, out) = m.drain(upTo: 4)!
    #expect(start == 0)
    #expect(out.floatChannelData![0][2] == 0.5)
    #expect(out.floatChannelData![1][2] == 0.5)
}

@Test func sourcesAreSummedAndClipped() {
    let m = AudioMixer()
    m.push(pcm([0.7, 0.7], channels: 2), from: .system, mediaTime: 0)
    m.push(pcm([0.2, 0.7], channels: 1), from: .mic, mediaTime: 0)
    let (_, out) = m.drain(upTo: 2)!
    #expect(abs(out.floatChannelData![0][0] - 0.9) < 0.0001)
    #expect(out.floatChannelData![0][1] == 1)
}

@Test func silentSourceDoesNotStallMix() {
    let m = AudioMixer()
    m.push(pcm([Float](repeating: 0.1, count: 4800), channels: 2), from: .system, mediaTime: 0)
    // Mic never delivers; the block still drains.
    let (_, out) = m.drain(upTo: 4800)!
    #expect(out.frameLength == 4800)
    #expect(m.drain(upTo: 4800) == nil)
    #expect(m.mixedUntil == 4800)
}

@Test func lateAudioBeforeMixPointIsDropped() {
    let m = AudioMixer()
    _ = m.drain(upTo: 100)
    m.push(pcm([1, 1, 1, 1], channels: 1), from: .mic, mediaTime: 0)
    #expect(m.deliveredUntil <= 100)
}

@Test func resamplerMakesSixteenKilohertzMono() {
    // The converter holds back a few hundred samples of filter latency on
    // the first buffer; over a stream the count converges on rate / 3.
    let r = Resampler.speech()
    var total = 0
    for _ in 0..<10 { total += r.samples(pcm([Float](repeating: 0.2, count: 4800), channels: 2)).count }
    #expect(abs(total - 16_000) < 400)
}
