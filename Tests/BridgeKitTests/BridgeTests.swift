import Foundation
import Testing
@testable import BridgeKit

private func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
}

@Test func rangeRequestParsing() {
    typealias H = MediaSchemeHandler
    #expect(H.parseRange("bytes=0-1", size: 100) == .init(start: 0, end: 1))
    #expect(H.parseRange("bytes=50-", size: 100) == .init(start: 50, end: 99))
    #expect(H.parseRange("bytes=-10", size: 100) == .init(start: 90, end: 99))
    #expect(H.parseRange("bytes=90-500", size: 100) == .init(start: 90, end: 99))
    #expect(H.parseRange("bytes=200-", size: 100) == nil)
    #expect(H.parseRange(nil, size: 100) == nil)
}

@Test func unknownMethodReturnsNativeError() async {
    let router = BridgeRouter()
    let reply = await router.handle(method: "nope", params: [:])
    #expect(reply["ok"] as? Bool == false)
    #expect((reply["error"] as? [String: Any])?["code"] as? String == "InvalidParams")
}

@Test func routerDecodesParamsAndEncodesResult() async {
    struct P: Codable { var id: String }
    let router = BridgeRouter()
    router.register("echo") { (p: P) in ["got": p.id] }
    router.register("null") { (_: NoParams) in Nothing() }
    let reply = await router.handle(method: "echo", params: ["id": "x"])
    #expect((reply["value"] as? [String: String])?["got"] == "x")
    let bad = await router.handle(method: "echo", params: ["nope": 1])
    #expect((bad["error"] as? [String: Any])?["code"] as? String == "InvalidParams")
    let null = await router.handle(method: "null", params: [:])
    #expect(null["value"] is NSNull)
}

@Test func contractFixturesDecode() throws {
    let detail = try JSONDecoder().decode(RecordingDetailDTO.self, from: Data(contentsOf: fixture("detail.json")))
    #expect(detail.recording.id == "rec-1")
    #expect(detail.segments.count == 4)
    #expect(detail.segments[3].originalText == "Grate.")
    // Round trip keeps every key the TypeScript schema expects.
    let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(detail)) as! [String: Any]
    let rec = back["recording"] as! [String: Any]
    for key in ["id", "title", "startedAt", "durationMs", "sizeBytes", "status", "transcriptStatus", "fileMissing", "hasSourceAudio", "segmentCount", "thumbnailCount"] {
        #expect(rec[key] != nil, "missing \(key)")
    }
}

@Test func formatterProducesSrtViaJavaScriptCore() throws {
    let detail = try JSONDecoder().decode(RecordingDetailDTO.self, from: Data(contentsOf: fixture("detail.json")))
    let srt = try TranscriptFormatter(script: fixture("core.jsc.js")).format(detail, as: "srt")
    #expect(srt == (try String(contentsOf: fixture("detail.srt"), encoding: .utf8)))
}

@Test func formatterRejectsUnknownFormat() throws {
    let detail = try JSONDecoder().decode(RecordingDetailDTO.self, from: Data(contentsOf: fixture("detail.json")))
    #expect(throws: BridgeFailure.self) { try TranscriptFormatter(script: fixture("core.jsc.js")).format(detail, as: "docx") }
}

@Test func settingsDecodeWithDefaultsAndMerge() throws {
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"quality":0.5}"#.utf8))
    #expect(s.quality == 0.5)
    #expect(s.scale == 0.8)
    #expect(s.copyFormat == "clean")
    let merged = try s.merging(["copyFormat": "plain", "fps": 7])
    #expect(merged.copyFormat == "plain")
    #expect(merged.validated.fps == 30)
}

@Test func eventEncodesWithTag() throws {
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BridgeEvent.retranscribeProgress(recordingId: "a", fraction: 0.5))) as! [String: Any]
    #expect(json["_tag"] as? String == "RetranscribeProgress")
    #expect(json["fraction"] as? Double == 0.5)
}
