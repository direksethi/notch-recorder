import CoreMedia
import Testing
@testable import RecorderKit

@Test func outputSizeFor5120x2160Is4096x1728() {
    #expect(RecordingSettings().outputSize(for: CGSize(width: 5120, height: 2160)) == CGSize(width: 4096, height: 1728))
    #expect(RecordingSettings().outputSize(for: CGSize(width: 1511, height: 983)) == CGSize(width: 1208, height: 786))
    #expect(RecordingSettings().keyframeInterval == 60)
}

@Test func macBookRetinaScreenScalesToFourThirdsOfPoints() {
    let s = RecordingSettings()
    // 14" MacBook Pro: 3024x1964 pixels at 2x.
    #expect(s.outputSize(for: CGSize(width: 3024, height: 1964), backingScale: 2) == CGSize(width: 2016, height: 1308))
    // 16" MacBook Pro: 3456x2234 pixels at 2x.
    #expect(s.outputSize(for: CGSize(width: 3456, height: 2234), backingScale: 2) == CGSize(width: 2304, height: 1488))
    // A 5120x2160 monitor is not Retina and keeps the 0.8 scale.
    #expect(s.outputSize(for: CGSize(width: 5120, height: 2160), backingScale: 1) == CGSize(width: 4096, height: 1728))
}

@Test func pacerCountsFramesAtThirtyFps() {
    var p = FramePacer(fps: 30)
    p.begin(at: 100)
    #expect(p.frameIndex(at: 101) == 30)
    #expect(p.pts(for: 30) == CMTime(value: 30, timescale: 30))
}

@Test func pausedTimeIsExcludedFromTimestamps() {
    var p = FramePacer(fps: 30)
    p.begin(at: 0)
    p.pause(at: 10)
    #expect(p.mediaTime(at: 500) == 10)
    p.resume(at: 600)
    #expect(p.mediaTime(at: 605) == 15)
    #expect(p.frameIndex(at: 605) == 450)
}

@Test func diskGuardVerdicts() {
    let g = DiskSpaceGuard()
    #expect(g.verdict(freeBytes: 10_000_000_000) == .fine)
    #expect(g.verdict(freeBytes: 4_000_000_000) == .warn)
    #expect(g.verdict(freeBytes: 500_000_000) == .stop)
}
