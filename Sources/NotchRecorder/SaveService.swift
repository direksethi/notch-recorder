import BridgeKit
import Common
import Foundation
import LibraryKit
import RecorderKit

/// Moves a finished recording from staging to its folder, names it, and
/// optionally writes transcript files.
struct SaveService: Sendable {
    let repo: LibraryRepository
    let paths: AppPaths
    let files: FileOps
    let formatter: TranscriptFormatter?

    struct Result: Equatable {
        var videoURL: URL
        var exported: [URL]
    }

    /// Exports are best effort: a failed export never undoes the save.
    func save(id: String, title: String, videoFolder: URL, exportFolder: URL?, exportFormats: [String]) throws -> Result {
        let row = try repo.recording(id: id)
        guard let current = row.currentVideoPath.map(URL.init(fileURLWithPath:)), files.exists(current) else {
            throw BridgeFailure(.FileMissing, "The video file for this recording is missing.")
        }
        let name = RecordingName.sanitize(title)
        try files.createFolder(videoFolder)
        var destination = current
        if current.deletingLastPathComponent().standardizedFileURL != videoFolder.standardizedFileURL
            || current.deletingPathExtension().lastPathComponent != name {
            destination = RecordingName.uniqueURL(in: videoFolder, base: name, ext: "mp4", exists: files.exists)
            do {
                try files.move(current, to: destination)
            } catch {
                throw BridgeFailure(.Failed, "Couldn't move the video to \(videoFolder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        try repo.modify(id) {
            $0.title = name
            $0.videoPath = destination.path
            $0.stagingPath = nil
            $0.status = .saved
            $0.errorMessage = nil
        }
        var exported: [URL] = []
        if let exportFolder {
            exported = (try? export(id: id, folder: exportFolder, formats: exportFormats)) ?? []
        }
        return Result(videoURL: destination, exported: exported)
    }

    func export(id: String, folder: URL, formats: [String]) throws -> [URL] {
        guard let formatter else { return [] }
        let detail = try detailDTO(id: id)
        try files.createFolder(folder)
        var out: [URL] = []
        for format in formats {
            let text = try formatter.format(detail, as: format)
            let url = RecordingName.uniqueURL(in: folder, base: RecordingName.sanitize(detail.recording.title), ext: format, exists: files.exists)
            try files.write(text, to: url)
            out.append(url)
        }
        return out
    }

    func detailDTO(id: String) throws -> RecordingDetailDTO {
        let summary = try repo.listRecordings().first { $0.recording.id == id }
            ?? RecordingSummary(recording: try repo.recording(id: id), preview: nil, previewSource: nil, segmentCount: 0, fileMissing: false)
        return RecordingDetailDTO(
            recording: RecordingSummaryDTO(summary),
            segments: try repo.segments(recordingId: id).map(SegmentDTO.init))
    }

    /// Removes everything belonging to a recording except (optionally) the video.
    func removeArtifacts(of row: RecordingRow, video: Bool) {
        if video, let p = row.currentVideoPath {
            let url = URL(fileURLWithPath: p)
            if row.status == .saved { try? files.trash(url) } else { files.remove(url) }
            files.remove(MovieWriter.workingURL(for: url))
        }
        for p in [row.micAudioPath, row.systemAudioPath].compactMap({ $0 }) { files.remove(URL(fileURLWithPath: p)) }
        files.remove(paths.thumbnailDirectory(for: row.id))
    }
}
