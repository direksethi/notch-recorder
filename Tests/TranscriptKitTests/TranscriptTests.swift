import AVFoundation
import Common
import Foundation
import Testing
@testable import TranscriptKit

/// Speech is any chunk louder than 0.05. Text is fixed per source unless set.
actor FakeEngine: SpeechEngine {
    var texts: [AudioSource: String] = [.me: "hello from me", .others: "hello from them", .speaker: "mixed audio"]
    var failTranscribe = false
    var failLoad = false
    var transcribeCalls = 0
    var loaded = false

    func set(_ source: AudioSource, _ text: String) { texts[source] = text }
    func setFailTranscribe(_ v: Bool) { failTranscribe = v }
    func setFailLoad(_ v: Bool) { failLoad = v }

    func load() async throws {
        if failLoad { throw TranscriptError.modelUnavailable("fake") }
        loaded = true
    }
    func unload() async { loaded = false }
    func vadProbability(_ chunk: [Float], source: AudioSource) async throws -> Float {
        let mean = chunk.reduce(0) { $0 + abs($1) } / Float(max(1, chunk.count))
        return mean > 0.05 ? 0.9 : 0.05
    }
    func transcribe(_ samples: [Float], source: AudioSource) async throws -> (text: String, confidence: Double) {
        transcribeCalls += 1
        if failTranscribe { throw TranscriptError.modelUnavailable("boom") }
        return (texts[source] ?? "", 0.9)
    }
}

let speech = [Float](repeating: 0.3, count: 4096)
let quiet = [Float](repeating: 0, count: 4096)

func run(_ seg: inout UtteranceSegmenter, _ pattern: [Bool]) -> [UtteranceSegmenter.Output] {
    var out: [UtteranceSegmenter.Output] = []
    for (i, loud) in pattern.enumerated() {
        out += seg.push(loud ? speech : quiet, startSample: Int64(i * 4096), probability: loud ? 0.9 : 0.05)
    }
    return out
}

@Test func speechStartsAndEndsProducesOneFinal() {
    var seg = UtteranceSegmenter(partials: false)
    let out = run(&seg, [false, true, true, true, false, false, false, false])
    #expect(out.count == 1)
    guard case .final(let samples, let start, let end) = out[0] else { Issue.record("not final"); return }
    #expect(start == 0) // pre-roll chunk included
    #expect(end - start == Int64(samples.count))
    // 4 chunks of audio (pre-roll + 3 speech) plus 200 ms of trailing silence.
    #expect(samples.count == 4 * 4096 + 3200)
}

@Test func partialEverySecondWhileSpeaking() {
    var seg = UtteranceSegmenter(partials: true)
    let out = run(&seg, Array(repeating: true, count: 12))
    let partials = out.filter { if case .partial = $0 { true } else { false } }
    // 12 chunks is about 3 s of speech: one partial per second.
    #expect(partials.count == 3)
}

@Test func forcedFinalAt14Seconds() {
    var seg = UtteranceSegmenter(partials: false)
    let out = run(&seg, Array(repeating: true, count: 60))
    let finals = out.compactMap { o -> Int? in if case .final(let s, _, _) = o { s.count } else { nil } }
    #expect(finals.count == 1)
    #expect(finals[0] >= 224_000)
    #expect(seg.isSpeaking)
}

@Test func tooShortBlipIsIgnored() {
    var seg = UtteranceSegmenter(partials: false)
    seg.minLength = 20_000
    #expect(run(&seg, [true, false, false, false]).isEmpty)
}

@Test func flushEndsUtteranceInProgress() {
    var seg = UtteranceSegmenter(partials: false)
    _ = run(&seg, [true, true])
    #expect(seg.flush().count == 1)
    #expect(!seg.isSpeaking)
}

@Test func echoDuplicateDropped() {
    let d = EchoDeduper()
    let them = SegmentDraft(source: .others, startMs: 1000, endMs: 3000, text: "Can you share your screen again?", confidence: 1)
    let me = SegmentDraft(source: .me, startMs: 1200, endMs: 3100, text: "can you share your screen again", confidence: 1)
    #expect(d.shouldDrop(me: me, others: [them]))
}

@Test func distinctTextKept() {
    let d = EchoDeduper()
    let them = SegmentDraft(source: .others, startMs: 1000, endMs: 3000, text: "Can you share your screen again?", confidence: 1)
    let me = SegmentDraft(source: .me, startMs: 1200, endMs: 3100, text: "Sure, one second, let me find it", confidence: 1)
    let late = SegmentDraft(source: .me, startMs: 9000, endMs: 9500, text: "can you share your screen again", confidence: 1)
    #expect(!d.shouldDrop(me: me, others: [them]))
    #expect(!d.shouldDrop(me: late, others: [them]))
}

final class Collector: @unchecked Sendable {
    let lock = NSLock()
    var finals: [SegmentDraft] = []
    var partials: [(AudioSource, String)] = []
    var statuses: [TranscriberStatus] = []
    func add(_ d: SegmentDraft) { lock.lock(); finals.append(d); lock.unlock() }
    func partial(_ s: AudioSource, _ t: String) { lock.lock(); partials.append((s, t)); lock.unlock() }
    func status(_ s: TranscriberStatus) { lock.lock(); statuses.append(s); lock.unlock() }
}

func makeTranscriber(_ engine: FakeEngine, _ c: Collector) -> LiveTranscriber {
    LiveTranscriber(engine: engine, onPartial: { c.partial($0, $1) }, onFinal: { c.add($0) }, onStatus: { c.status($0) })
}

@Test func liveTranscriberEmitsFinalsForBothSources() async {
    let engine = FakeEngine()
    let c = Collector()
    let t = makeTranscriber(engine, c)
    await t.start()
    let audio = [Float](repeating: 0, count: 8192) + [Float](repeating: 0.3, count: 16_384) + [Float](repeating: 0, count: 16_384)
    await t.feed(source: .others, samples: audio, startSample: 0)
    await t.feed(source: .me, samples: audio, startSample: 160_000)
    await t.finish()
    #expect(Set(c.finals.map(\.text)) == ["hello from me", "hello from them"])
    let mine = c.finals.first { $0.source == .me }!
    #expect(mine.startMs >= 10_000)
    #expect(c.statuses.last == .finished)
}

@Test func echoedMicSegmentIsDroppedLive() async {
    let engine = FakeEngine()
    await engine.set(.me, "hello from them")
    let c = Collector()
    let t = makeTranscriber(engine, c)
    await t.start()
    let audio = [Float](repeating: 0.3, count: 16_384) + [Float](repeating: 0, count: 16_384)
    await t.feed(source: .me, samples: audio, startSample: 0)
    await t.feed(source: .others, samples: audio, startSample: 0)
    await t.finish()
    #expect(c.finals.map(\.source) == [.others])
}

@Test func engineFailureMarksTranscriptFailedButKeepsRunning() async {
    let engine = FakeEngine()
    await engine.setFailTranscribe(true)
    let c = Collector()
    let t = makeTranscriber(engine, c)
    await t.start()
    let burst = [Float](repeating: 0.3, count: 8192) + [Float](repeating: 0, count: 16_384)
    for i in 0..<5 {
        await t.feed(source: .others, samples: burst, startSample: Int64(i * burst.count))
    }
    if case .failed = await t.currentStatus {} else { Issue.record("expected failed") }
    // Further audio is accepted without throwing or transcribing.
    let calls = await engine.transcribeCalls
    await t.feed(source: .others, samples: burst, startSample: 999_999)
    #expect(await engine.transcribeCalls == calls)
    await t.finish()
}

@Test func modelLoadFailureIsReported() async {
    let engine = FakeEngine()
    await engine.setFailLoad(true)
    let c = Collector()
    let t = makeTranscriber(engine, c)
    await t.start()
    if case .failed(let m) = await t.currentStatus { #expect(m.contains("speech model")) } else { Issue.record("expected failed") }
}

func writeCAF(_ samples: [Float]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).caf")
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
    let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    b.frameLength = AVAudioFrameCount(samples.count)
    for (i, s) in samples.enumerated() { b.floatChannelData![0][i] = s }
    try file.write(from: b)
    return url
}

@Test func retranscribeKeepsSourcesAndResumesFromOffset() async throws {
    // Speech at 1-2 s and 6-7 s.
    var audio = [Float](repeating: 0, count: 16_000 * 8)
    for i in 16_000..<32_000 { audio[i] = 0.3 }
    for i in 96_000..<112_000 { audio[i] = 0.3 }
    let mic = try writeCAF(audio)
    let sys = try writeCAF(audio)
    let r = Retranscriber(engine: FakeEngine())
    let all = try await r.run(.init(micAudio: mic, systemAudio: sys, video: nil, fromMs: 0, durationMs: 8_000)) { _ in }
    #expect(all.count == 4)
    #expect(Set(all.map(\.source)) == [.me, .others])
    let tail = try await r.run(.init(micAudio: mic, systemAudio: nil, video: nil, fromMs: 4_000, durationMs: 8_000)) { _ in }
    #expect(tail.count == 1)
    #expect(tail[0].startMs >= 5_500 && tail[0].startMs <= 6_100)
}

@Test func retranscribeWithoutAudioFails() async {
    let r = Retranscriber(engine: FakeEngine())
    await #expect(throws: TranscriptError.self) {
        _ = try await r.run(.init(micAudio: nil, systemAudio: nil, video: nil, fromMs: 0, durationMs: 1)) { _ in }
    }
}

actor SlowEngine: SpeechEngine {
    let inner = FakeEngine()
    func load() async throws {
        try await Task.sleep(for: .milliseconds(300))
        try await inner.load()
    }
    func unload() async { await inner.unload() }
    func vadProbability(_ chunk: [Float], source: AudioSource) async throws -> Float { try await inner.vadProbability(chunk, source: source) }
    func transcribe(_ samples: [Float], source: AudioSource) async throws -> (text: String, confidence: Double) { try await inner.transcribe(samples, source: source) }
}

@Test func audioDuringModelLoadIsNotLost() async {
    let c = Collector()
    let t = LiveTranscriber(engine: SlowEngine(), onPartial: { c.partial($0, $1) }, onFinal: { c.add($0) }, onStatus: { c.status($0) })
    let loading = Task { await t.start() }
    try? await Task.sleep(for: .milliseconds(50))
    let audio = [Float](repeating: 0.3, count: 16_384) + [Float](repeating: 0, count: 16_384)
    await t.feed(source: .others, samples: audio, startSample: 0)
    await loading.value
    await t.finish()
    #expect(c.finals.map(\.text) == ["hello from them"])
}
