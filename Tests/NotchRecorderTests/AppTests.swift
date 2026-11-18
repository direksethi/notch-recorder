import BridgeKit
import Common
import Foundation
import LibraryKit
import Testing
@testable import NotchRecorder

/// In-memory files.
final class FakeFiles: FileOps, @unchecked Sendable {
    let lock = NSLock()
    var files: [String: Int64] = [:]
    var trashed: [String] = []
    var written: [String: String] = [:]
    var failMove = false

    init(_ paths: [String] = []) { for p in paths { files[p] = 100 } }

    func exists(_ url: URL) -> Bool { lock.withLock { files[url.path] != nil } }
    func move(_ from: URL, to: URL) throws {
        try lock.withLock {
            if failMove { throw CocoaError(.fileWriteNoPermission) }
            guard let size = files.removeValue(forKey: from.path) else { throw CocoaError(.fileNoSuchFile) }
            files[to.path] = size
        }
    }
    func createFolder(_ url: URL) throws {}
    func trash(_ url: URL) throws { lock.withLock { files[url.path] = nil; trashed.append(url.path) } }
    func remove(_ url: URL) { lock.withLock { files = files.filter { !$0.key.hasPrefix(url.path) } } }
    func write(_ text: String, to url: URL) throws { lock.withLock { files[url.path] = Int64(text.count); written[url.path] = text } }
    func size(_ url: URL) -> Int64 { lock.withLock { files[url.path] ?? 0 } }
    func list(_ folder: URL) -> [URL] {
        lock.withLock { files.keys.filter { URL(fileURLWithPath: $0).deletingLastPathComponent().path == folder.path }.map(URL.init(fileURLWithPath:)) }
    }
}

struct FakeMedia: RecoveryMedia {
    let files: FakeFiles
    var duration: Int64? = 60_000
    func remux(_ mov: URL, to mp4: URL) async throws { try files.move(mov, to: mp4) }
    func durationMs(_ url: URL) async -> Int64? { files.exists(url) ? duration : nil }
}

let paths = AppPaths(root: URL(fileURLWithPath: "/app"))

func repo() throws -> LibraryRepository {
    LibraryRepository(db: try LibraryDatabase.open(at: nil))
}

@Test func quitWhileRecordingDefersTermination() {
    #expect(TerminationPolicy.decide(isRecording: true, hasJob: false, systemIsShuttingDown: false) == .ask)
    #expect(TerminationPolicy.decide(isRecording: true, hasJob: false, systemIsShuttingDown: true) == .stopThenQuit)
    #expect(TerminationPolicy.decide(isRecording: false, hasJob: true, systemIsShuttingDown: false) == .stopThenQuit)
    #expect(TerminationPolicy.decide(isRecording: false, hasJob: false, systemIsShuttingDown: false) == .now)
}

@Test func recoversRecordingRowAndQueuesTailTranscription() async throws {
    let r = try repo()
    let files = FakeFiles(["/app/Staging/a.mov", "/app/Audio/a-mic.caf"])
    var row = RecordingRow(id: "a", title: "t", startedAt: Date(), stagingPath: "/app/Staging/a.mp4", status: .recording, transcriptStatus: .live, micAudioPath: "/app/Audio/a-mic.caf")
    row.transcribedUntilMs = 10_000
    try r.insert(row)
    let ids = await Recovery(repo: r, paths: paths, files: files, media: FakeMedia(files: files)).run()
    #expect(ids == ["a"])
    let after = try r.recording(id: "a")
    #expect(after.status == .unsaved)
    #expect(after.durationMs == 60_000)
    #expect(after.transcriptStatus == .retranscribing)
    #expect(after.errorMessage == Recovery.recoveredNote)
    #expect(files.exists(URL(fileURLWithPath: "/app/Staging/a.mp4")))
}

@Test func recoveryWithNoVideoMarksFailed() async throws {
    let r = try repo()
    let files = FakeFiles()
    try r.insert(RecordingRow(id: "b", title: "t", startedAt: Date(), stagingPath: "/app/Staging/b.mp4", status: .recording))
    _ = await Recovery(repo: r, paths: paths, files: files, media: FakeMedia(files: files)).run()
    #expect(try r.recording(id: "b").status == .failed)
}

@Test func completeTranscriptIsNotRequeued() async throws {
    let r = try repo()
    let files = FakeFiles(["/app/Staging/c.mp4", "/app/Audio/c-mic.caf"])
    var row = RecordingRow(id: "c", title: "t", startedAt: Date(), stagingPath: "/app/Staging/c.mp4", status: .recording, transcriptStatus: .live, micAudioPath: "/app/Audio/c-mic.caf")
    row.transcribedUntilMs = 59_000
    try r.insert(row)
    let ids = await Recovery(repo: r, paths: paths, files: files, media: FakeMedia(files: files)).run()
    #expect(ids.isEmpty)
    #expect(try r.recording(id: "c").transcriptStatus == .complete)
}

@Test func orphanStagingFileIsRegistered() async throws {
    let r = try repo()
    let files = FakeFiles(["/app/Staging/zzz.mov"])
    let ids = await Recovery(repo: r, paths: paths, files: files, media: FakeMedia(files: files)).run()
    #expect(ids.count == 1)
    let row = try r.recording(id: ids[0])
    #expect(row.stagingPath == "/app/Staging/zzz.mp4")
    #expect(row.status == .unsaved)
    #expect(row.transcriptStatus == .retranscribing)
}

@Test func saveMovesFileAndAvoidsNameCollision() throws {
    let r = try repo()
    let files = FakeFiles(["/app/Staging/a.mp4", "/videos/Call.mp4"])
    try r.insert(RecordingRow(id: "a", title: "t", startedAt: Date(), stagingPath: "/app/Staging/a.mp4", status: .unsaved))
    let saver = SaveService(repo: r, paths: paths, files: files, formatter: nil)
    let result = try saver.save(id: "a", title: "Call", videoFolder: URL(fileURLWithPath: "/videos"), exportFolder: nil, exportFormats: [])
    #expect(result.videoURL.path == "/videos/Call 2.mp4")
    let row = try r.recording(id: "a")
    #expect(row.status == .saved)
    #expect(row.videoPath == "/videos/Call 2.mp4")
    #expect(row.stagingPath == nil)
    #expect(!files.exists(URL(fileURLWithPath: "/app/Staging/a.mp4")))
}

@Test func saveFailureKeepsRecordingUnsaved() throws {
    let r = try repo()
    let files = FakeFiles(["/app/Staging/a.mp4"])
    files.failMove = true
    try r.insert(RecordingRow(id: "a", title: "t", startedAt: Date(), stagingPath: "/app/Staging/a.mp4", status: .unsaved))
    let saver = SaveService(repo: r, paths: paths, files: files, formatter: nil)
    #expect(throws: BridgeFailure.self) {
        try saver.save(id: "a", title: "Call", videoFolder: URL(fileURLWithPath: "/videos"), exportFolder: nil, exportFormats: [])
    }
    #expect(try r.recording(id: "a").status == .unsaved)
}

@Test func saveWithMissingFileReportsFileMissing() throws {
    let r = try repo()
    try r.insert(RecordingRow(id: "a", title: "t", startedAt: Date(), stagingPath: "/app/Staging/a.mp4", status: .unsaved))
    let saver = SaveService(repo: r, paths: paths, files: FakeFiles(), formatter: nil)
    #expect(throws: BridgeFailure(.FileMissing, "The video file for this recording is missing.")) {
        try saver.save(id: "a", title: "x", videoFolder: URL(fileURLWithPath: "/v"), exportFolder: nil, exportFormats: [])
    }
}

@Test func discardingUnsavedRemovesEverything() throws {
    let files = FakeFiles(["/app/Staging/a.mp4", "/app/Audio/a-mic.caf", "/app/Thumbnails/a/0.jpg"])
    let row = RecordingRow(id: "a", title: "t", startedAt: Date(), stagingPath: "/app/Staging/a.mp4", status: .unsaved, micAudioPath: "/app/Audio/a-mic.caf")
    SaveService(repo: try repo(), paths: paths, files: files, formatter: nil).removeArtifacts(of: row, video: true)
    #expect(files.files.isEmpty)
    #expect(files.trashed.isEmpty)
}
