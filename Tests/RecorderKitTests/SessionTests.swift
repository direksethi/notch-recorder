import AVFoundation
import Testing
@testable import RecorderKit

private func session(_ source: FakeScreenSource, free: Int64 = .max) -> RecordingSession {
    let video = tempURL("s.mp4")
    let dir = video.deletingLastPathComponent()
    return RecordingSession(
        id: "t",
        settings: RecordingSettings(),
        paths: .init(video: video, micAudio: dir.appendingPathComponent("mic.caf"), systemAudio: dir.appendingPathComponent("sys.caf")),
        source: source,
        freeBytes: { free })
}

@Test func stopDuringRecordingFinalisesPlayableFile() async throws {
    let source = FakeScreenSource()
    let s = session(source)
    try await s.start()
    try await Task.sleep(for: .seconds(2))
    let output = try #require(await s.stop())
    #expect(output.width == 512 && output.height == 216)
    #expect(abs(output.duration - 2) < 0.4)
    let asset = AVURLAsset(url: output.videoURL)
    #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    #expect(output.micAudioURL != nil)
    if case .finished = s.currentState {} else { Issue.record("expected finished, got \(s.currentState)") }
}

@Test func speechEventsCarryBothSources() async throws {
    let source = FakeScreenSource()
    let s = session(source)
    try await s.start()
    var sources = Set<String>()
    let collector = Task {
        for await e in s.events {
            if case .speech(let src, _, _) = e { sources.insert(src.rawValue) }
        }
        return sources
    }
    try await Task.sleep(for: .seconds(1))
    await s.stop()
    #expect(await collector.value == ["me", "others"])
}

@Test func pauseResumeKeepsSingleFile() async throws {
    let source = FakeScreenSource()
    let s = session(source)
    try await s.start()
    try await Task.sleep(for: .seconds(1))
    await s.pause()
    try await Task.sleep(for: .seconds(1))
    await s.resume()
    try await Task.sleep(for: .seconds(1))
    let output = try #require(await s.stop())
    #expect(source.startCount == 2)
    #expect(abs(output.duration - 2) < 0.4)
}

@Test func streamErrorRestartsThenFailsAfterThree() async throws {
    let source = FakeScreenSource()
    let s = session(source)
    try await s.start()
    source.emitError()
    try await Task.sleep(for: .seconds(1))
    #expect(source.startCount == 2)
    if case .recording = s.currentState {} else { Issue.record("should still be recording") }
    for _ in 0..<4 { source.emitError() }
    try await Task.sleep(for: .seconds(2))
    if case .failed(let e, let output) = s.currentState {
        #expect(e == .captureFailed("Screen capture failed: display disconnected"))
        #expect(output != nil)
    } else {
        Issue.record("expected failed, got \(s.currentState)")
    }
}

@Test func diskUnder1GBStopsCleanly() async throws {
    let source = FakeScreenSource()
    let s = session(source, free: 500_000_000)
    try await s.start()
    try await Task.sleep(for: .seconds(2))
    if case .failed(let e, let output) = s.currentState {
        #expect(e == .diskFull)
        #expect(output != nil)
    } else {
        Issue.record("expected diskFull, got \(s.currentState)")
    }
}

@Test func startFailureReportsAndLeavesNoSession() async throws {
    let source = FakeScreenSource()
    source.failStart = true
    let s = session(source)
    await #expect(throws: RecorderError.self) { try await s.start() }
    if case .failed = s.currentState {} else { Issue.record("expected failed") }
}
