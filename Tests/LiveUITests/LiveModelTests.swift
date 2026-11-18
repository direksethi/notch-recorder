import Common
import Testing
@testable import LiveUI

@MainActor
@Test func finalLineReplacesItsPartial() {
    let m = LiveModel()
    m.setPartial(.me, "hello wor")
    m.setPartial(.others, "good morn")
    m.addFinal(.me, "Hello world.")
    #expect(m.lines.map(\.text) == ["Hello world."])
    #expect(m.partials[.me] == nil)
    #expect(m.partials[.others] == "good morn")
}

@MainActor
@Test func keepsTheWholeTranscriptUpToTheCap() {
    let m = LiveModel()
    for i in 0..<(LiveModel.maxLines + 5) { m.addFinal(.others, "line \(i)") }
    #expect(m.lines.count == LiveModel.maxLines)
    #expect(m.lines.first?.text == "line 5")
}

@MainActor
@Test func resetClearsTheLastRecording() {
    let m = LiveModel()
    m.addFinal(.me, "a")
    m.setPartial(.others, "b")
    m.elapsed = 12
    m.warning = "w"
    m.transcriptNote = "n"
    m.reset()
    #expect(m.lines.isEmpty && m.partials.isEmpty && m.elapsed == 0 && m.warning == nil && m.transcriptNote == nil)
}

@MainActor
@Test func onlyNoticesAndHiddenCountAsInactive() {
    let m = LiveModel()
    for phase: LivePhase in [.preparing, .recording, .paused, .finishing] {
        m.phase = phase
        #expect(m.isActive)
    }
    for phase: LivePhase in [.hidden, .notice(title: "t", message: "m")] {
        m.phase = phase
        #expect(!m.isActive)
    }
}

@MainActor
@Test func clockFormatsMinutesAndHours() {
    #expect(LiveModel.clock(65) == "01:05")
    #expect(LiveModel.clock(3725) == "1:02:05")
}
