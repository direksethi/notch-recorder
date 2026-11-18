import AppKit
import BridgeKit
import Common
import Foundation
import LibraryKit
import UniformTypeIdentifiers

/// Every bridge method the Library UI can call.
@MainActor
final class LibraryService {
    private let repo: LibraryRepository
    private let coordinator: AppCoordinator
    private let jobs: JobQueue
    private let saver: SaveService
    private let settings: SettingsStore

    init(repo: LibraryRepository, coordinator: AppCoordinator, jobs: JobQueue, saver: SaveService, settings: SettingsStore) {
        self.repo = repo
        self.coordinator = coordinator
        self.jobs = jobs
        self.saver = saver
        self.settings = settings
    }

    struct RenameParams: Decodable { var id: String; var title: String }
    struct DeleteParams: Decodable { var id: String; var deleteFiles: Bool }
    struct SaveParams: Decodable { var id: String; var title: String; var videoFolder: String }
    struct SearchParams: Decodable { var query: String; var source: String? }
    struct EditParams: Decodable { var id: Int64; var text: String }
    struct ExportParams: Decodable { var id: String; var format: String; var folder: String?; var filename: String; var content: String }
    struct ClipboardParams: Decodable { var text: String }
    struct FolderParams: Decodable { var initial: String?; var prompt: String? }
    struct KindParams: Decodable { var kind: String }

    func register(on router: BridgeRouter) {
        router.register("recordings.list") { [unowned self] (_: NoParams) in try await self.list() }
        router.register("recordings.get") { [unowned self] (p: IdParams) in try await self.detail(p.id) }
        router.register("recordings.rename") { [unowned self] (p: RenameParams) in try await self.rename(p) }
        router.register("recordings.delete") { [unowned self] (p: DeleteParams) in try await self.delete(p) }
        router.register("recordings.reveal") { [unowned self] (p: IdParams) in try await self.reveal(p.id) }
        router.register("recordings.openExternal") { [unowned self] (p: IdParams) in try await self.openExternal(p.id) }
        router.register("recordings.save") { [unowned self] (p: SaveParams) in try await self.save(p) }
        router.register("recordings.discard") { [unowned self] (p: IdParams) in await self.discard(p.id) }
        router.register("recordings.locate") { [unowned self] (p: IdParams) in try await self.locate(p.id) }
        router.register("transcripts.search") { [unowned self] (p: SearchParams) in try await self.search(p) }
        router.register("transcripts.editSegment") { [unowned self] (p: EditParams) in try await self.edit(p) }
        router.register("transcripts.retranscribe") { [unowned self] (p: IdParams) in try await self.retranscribe(p.id) }
        router.register("transcripts.cancelRetranscribe") { [unowned self] (p: IdParams) in await self.cancelRetranscribe(p.id) }
        router.register("transcripts.exportFile") { [unowned self] (p: ExportParams) in try await self.exportFile(p) }
        router.register("clipboard.write") { [unowned self] (p: ClipboardParams) in await self.copy(p.text) }
        router.register("settings.get") { [unowned self] (_: NoParams) in await self.settings.current }
        router.register("settings.update") { [unowned self] (p: [String: JSONValue]) in try await self.updateSettings(p) }
        router.register("dialogs.chooseFolder") { (p: FolderParams) in await Dialogs.chooseFolder(initial: p.initial, prompt: p.prompt) }
        router.register("recorder.state") { [unowned self] (_: NoParams) in await self.coordinator.stateDTO }
        router.register("recorder.start") { [unowned self] (_: NoParams) in await self.startRecording() }
        router.register("recorder.stop") { [unowned self] (_: NoParams) in await self.stopRecording() }
        router.register("system.devices") { (_: NoParams) in await MainActor.run { Devices.list() } }
        router.register("system.permissions") { (_: NoParams) in
            PermissionsDTO(screen: Permissions.screen, microphone: Permissions.microphone == .authorized)
        }
        router.register("system.openPermissionSettings") { (p: KindParams) in
            await MainActor.run {
                if p.kind == "screen" && !Permissions.screen { Permissions.requestScreen() }
                Permissions.openSettings(p.kind)
            }
            return Nothing()
        }
    }

    // MARK: Recordings

    func list() throws -> [RecordingSummaryDTO] {
        try repo.listRecordings().map(RecordingSummaryDTO.init)
    }

    func summary(_ id: String) throws -> RecordingSummaryDTO {
        guard let s = try repo.listRecordings().first(where: { $0.recording.id == id }) else { throw LibraryError.notFound(id) }
        return RecordingSummaryDTO(s)
    }

    func detail(_ id: String) throws -> RecordingDetailDTO {
        try saver.detailDTO(id: id)
    }

    /// Renames the recording and, when saved, its video file too.
    func rename(_ p: RenameParams) throws -> RecordingSummaryDTO {
        let title = RecordingName.sanitize(p.title)
        let row = try repo.recording(id: p.id)
        var newPath = row.videoPath
        if row.status == .saved, let path = row.videoPath, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if url.deletingPathExtension().lastPathComponent != title {
                let dest = RecordingName.uniqueURL(in: url.deletingLastPathComponent(), base: title, ext: url.pathExtension)
                try FileManager.default.moveItem(at: url, to: dest)
                newPath = dest.path
            }
        }
        try repo.modify(p.id) {
            $0.title = title
            $0.videoPath = newPath
        }
        coordinator.publish(.libraryChanged(recordingId: p.id))
        return try summary(p.id)
    }

    func delete(_ p: DeleteParams) throws -> Nothing {
        if coordinator.stateDTO.recordingId == p.id { throw BridgeFailure(.Busy, "Stop the recording before deleting it.") }
        let row = try repo.recording(id: p.id)
        jobs.cancel(p.id)
        saver.removeArtifacts(of: row, video: p.deleteFiles || row.status != .saved)
        try repo.delete(id: p.id)
        coordinator.publish(.libraryChanged(recordingId: p.id))
        return Nothing()
    }

    private func videoURL(_ id: String) throws -> URL {
        let row = try repo.recording(id: id)
        guard let p = row.currentVideoPath, FileManager.default.fileExists(atPath: p) else {
            throw BridgeFailure(.FileMissing, "The video file can't be found. Use Locate to find it.")
        }
        return URL(fileURLWithPath: p)
    }

    func reveal(_ id: String) throws -> Nothing {
        NSWorkspace.shared.activateFileViewerSelecting([try videoURL(id)])
        return Nothing()
    }

    func openExternal(_ id: String) throws -> Nothing {
        NSWorkspace.shared.open(try videoURL(id))
        return Nothing()
    }

    func save(_ p: SaveParams) async throws -> RecordingSummaryDTO {
        let s = settings.current
        _ = try saver.save(
            id: p.id, title: p.title, videoFolder: URL(fileURLWithPath: p.videoFolder),
            exportFolder: s.exportOnSave ? URL(fileURLWithPath: s.exportFolder ?? p.videoFolder) : nil,
            exportFormats: s.exportFormats)
        coordinator.publish(.libraryChanged(recordingId: p.id))
        return try summary(p.id)
    }

    func discard(_ id: String) async -> Nothing {
        await coordinator.discard(id: id)
        return Nothing()
    }

    func locate(_ id: String) throws -> RecordingSummaryDTO? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Use file"
        panel.message = "Select the video file for this recording."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try repo.modify(id) {
            $0.videoPath = url.path
            $0.stagingPath = nil
            $0.status = .saved
        }
        coordinator.publish(.libraryChanged(recordingId: id))
        return try summary(id)
    }

    // MARK: Transcripts

    func search(_ p: SearchParams) throws -> [SearchHitDTO] {
        try repo.search(query: p.query, source: p.source.flatMap(AudioSource.init(rawValue:))).map(SearchHitDTO.init)
    }

    func edit(_ p: EditParams) throws -> SegmentDTO {
        let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw BridgeFailure(.InvalidParams, "Enter text for this line.") }
        return SegmentDTO(try repo.editSegment(id: p.id, text: text))
    }

    func retranscribe(_ id: String) throws -> Nothing {
        if coordinator.stateDTO.recordingId == id { throw BridgeFailure(.Busy, "This recording is still in progress.") }
        try repo.modify(id) {
            $0.transcribedUntilMs = 0
            $0.transcriptStatus = .retranscribing
        }
        jobs.enqueue(id)
        coordinator.publish(.libraryChanged(recordingId: id))
        return Nothing()
    }

    func cancelRetranscribe(_ id: String) -> Nothing {
        jobs.cancel(id)
        return Nothing()
    }

    /// Writes text the page formatted. Without a folder, asks where.
    func exportFile(_ p: ExportParams) throws -> String? {
        let filename = RecordingName.sanitize((p.filename as NSString).deletingPathExtension)
        let ext = (p.filename as NSString).pathExtension.isEmpty ? p.format : (p.filename as NSString).pathExtension
        let url: URL
        if let folder = p.folder {
            url = RecordingName.uniqueURL(in: URL(fileURLWithPath: folder), base: filename, ext: ext)
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(filename).\(ext)"
            if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
            panel.canCreateDirectories = true
            if let last = settings.current.exportFolder { panel.directoryURL = URL(fileURLWithPath: last) }
            NSApp.activate()
            guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
            url = chosen
            _ = try? settings.update(["exportFolder": chosen.deletingLastPathComponent().path])
        }
        do {
            try p.content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw BridgeFailure(.Failed, "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)")
        }
        return url.path
    }

    func copy(_ text: String) -> Nothing {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return Nothing()
    }

    func updateSettings(_ patch: [String: JSONValue]) throws -> AppSettings {
        try settings.update(patch.mapValues(\.any))
    }

    func startRecording() async -> RecorderStateDTO {
        await coordinator.start()
        return coordinator.stateDTO
    }

    func stopRecording() async -> RecorderStateDTO {
        await coordinator.stop()
        return coordinator.stateDTO
    }
}
