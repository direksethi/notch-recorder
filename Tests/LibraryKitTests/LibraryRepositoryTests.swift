import Common
import Foundation
import Testing
@testable import LibraryKit

private func makeRepo(existing: Set<String> = []) throws -> LibraryRepository {
    LibraryRepository(db: try LibraryDatabase.open(at: nil), fileExists: { existing.contains($0) })
}

private func recording(_ id: String, at offset: TimeInterval = 0, status: RecordingStatus = .saved, video: String? = "/v/\(UUID()).mp4") -> RecordingRow {
    RecordingRow(id: id, title: "Rec \(id)", startedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset), videoPath: video, status: status)
}

@Test func migrationsCreateTablesAndFts() throws {
    let repo = try makeRepo()
    let tables = try repo.db.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type IN ('table')") }
    #expect(tables.contains("recording"))
    #expect(tables.contains("segment"))
    #expect(tables.contains("segment_fts"))
    #expect(tables.contains("setting"))
}

@Test func appendSegmentIsSearchableAndAdvancesTranscribedUntil() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .others, startMs: 1000, endMs: 4000, text: "We need the pricing page this week"))
    let hits = try repo.search(query: "pricing")
    #expect(hits.count == 1)
    #expect(hits[0].highlighted.contains("\u{1}pricing\u{2}"))
    #expect(try repo.recording(id: "a").transcribedUntilMs == 4000)
}

@Test func searchMatchesPrefixes() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 0, endMs: 1, text: "deployment went fine"))
    #expect(try repo.search(query: "deploy").count == 1)
}

@Test func searchFiltersBySource() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 0, endMs: 1, text: "pricing from me"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .others, startMs: 2, endMs: 3, text: "pricing from them"))
    #expect(try repo.search(query: "pricing", source: .me).map(\.source) == [.me])
}

@Test func editSegmentKeepsOriginalText() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    let s = try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 0, endMs: 1, text: "fluid boys"))
    try repo.editSegment(id: s.id!, text: "FluidVoice")
    let edited = try repo.editSegment(id: s.id!, text: "FluidVoice app")
    #expect(edited.text == "FluidVoice app")
    #expect(edited.originalText == "fluid boys")
    #expect(try repo.search(query: "FluidVoice").count == 1)
}

@Test func missingFileIsReportedNotThrown() throws {
    let repo = try makeRepo(existing: ["/present.mp4"])
    try repo.insert(recording("here", at: 1, video: "/present.mp4"))
    try repo.insert(recording("gone", at: 0, video: "/gone.mp4"))
    let list = try repo.listRecordings()
    #expect(list.map(\.recording.id) == ["here", "gone"])
    #expect(list.map(\.fileMissing) == [false, true])
}

@Test func listIncludesPreviewAndSkipsDiscarded() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    try repo.insert(recording("d", status: .discarded))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .others, startMs: 5, endMs: 6, text: "second"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 0, endMs: 1, text: "first"))
    let list = try repo.listRecordings()
    #expect(list.count == 1)
    #expect(list[0].preview == "first")
    #expect(list[0].previewSource == .me)
    #expect(list[0].segmentCount == 2)
}

@Test func unfinishedRecordingsReturnsRecordingStatus() throws {
    let repo = try makeRepo()
    try repo.insert(recording("live", status: .recording))
    try repo.insert(recording("done"))
    var job = recording("job")
    job.transcriptStatus = .retranscribing
    try repo.insert(job)
    #expect(Set(try repo.unfinishedRecordings().map(\.id)) == ["live", "job"])
}

@Test func replaceSegmentsFromOffsetKeepsEarlierOnes() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 0, endMs: 900, text: "keep"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 1000, endMs: 2000, text: "drop"))
    try repo.replaceSegments(recordingId: "a", fromMs: 1000, with: [
        SegmentRow(recordingId: "a", source: .others, startMs: 1100, endMs: 2100, text: "new"),
    ])
    #expect(try repo.segments(recordingId: "a").map(\.text) == ["keep", "new"])
}

@Test func deleteCascadesSegments() throws {
    let repo = try makeRepo()
    try repo.insert(recording("a"))
    try repo.appendSegment(SegmentRow(recordingId: "a", source: .me, startMs: 0, endMs: 1, text: "x"))
    try repo.delete(id: "a")
    #expect(try repo.segments(recordingId: "a").isEmpty)
    #expect(throws: LibraryError.notFound("a")) { try repo.recording(id: "a") }
}

@Test func settingsUpsert() throws {
    let repo = try makeRepo()
    try repo.setSetting("k", "1")
    try repo.setSetting("k", "2")
    #expect(try repo.setting("k") == "2")
    #expect(try repo.setting("missing") == nil)
}

@Test func uniqueURLAddsSuffix() {
    let folder = URL(fileURLWithPath: "/x")
    let taken: Set<String> = ["/x/a.mp4", "/x/a 2.mp4"]
    let url = RecordingName.uniqueURL(in: folder, base: "a", ext: "mp4", exists: { taken.contains($0.path) })
    #expect(url.path == "/x/a 3.mp4")
    #expect(RecordingName.sanitize(" a/b:c ") == "a-b-c")
    #expect(RecordingName.sanitize("   ") == "Recording")
}
