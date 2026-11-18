import AVFoundation
import Common
import Foundation
import LibraryKit
import RecorderKit

/// What recovery needs from AVFoundation (faked in tests).
protocol RecoveryMedia: Sendable {
    func remux(_ mov: URL, to mp4: URL) async throws
    func durationMs(_ url: URL) async -> Int64?
}

struct LiveRecoveryMedia: RecoveryMedia {
    func remux(_ mov: URL, to mp4: URL) async throws { try await Remux.toMP4(from: mov, to: mp4) }
    func durationMs(_ url: URL) async -> Int64? {
        guard let s = try? await AVURLAsset(url: url).load(.duration).seconds, s.isFinite, s > 0 else { return nil }
        return Int64(s * 1000)
    }
}

/// Runs at launch. Anything left mid-recording by a crash, force quit or
/// power loss becomes an Unsaved recording with a playable file, and its
/// transcript is queued to be finished from the saved audio.
struct Recovery {
    let repo: LibraryRepository
    let paths: AppPaths
    let files: FileOps
    let media: RecoveryMedia

    static let recoveredNote = "Recovered after Notch Recorder quit unexpectedly."

    /// Returns ids whose transcript should be (re)transcribed.
    func run() async -> [String] {
        var queue: [String] = []
        for row in (try? repo.unfinishedRecordings()) ?? [] {
            if row.status == .recording {
                if let id = await recoverRecording(row) { queue.append(id) }
            } else if row.transcriptStatus == .retranscribing {
                queue.append(row.id)
            } else if row.transcriptStatus == .live {
                if let id = settleTranscript(row, durationMs: row.durationMs) { queue.append(id) }
            }
        }
        queue += await registerOrphans()
        return queue
    }

    private func recoverRecording(_ row: RecordingRow) async -> String? {
        guard let staged = row.stagingPath.map(URL.init(fileURLWithPath:)) else {
            try? repo.modify(row.id) { $0.status = .failed; $0.errorMessage = "The recording stopped before any video was written." }
            return nil
        }
        let working = MovieWriter.workingURL(for: staged)
        if !files.exists(staged) && files.exists(working) {
            do {
                try await media.remux(working, to: staged)
            } catch {
                Log.app.error("recovery remux failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard files.exists(staged), let duration = await media.durationMs(staged) else {
            try? repo.modify(row.id) { $0.status = .failed; $0.errorMessage = "The recording stopped before any video was written." }
            return nil
        }
        try? repo.modify(row.id) {
            $0.status = .unsaved
            $0.durationMs = duration
            $0.sizeBytes = files.size(staged)
            $0.endedAt = $0.startedAt.addingTimeInterval(Double(duration) / 1000)
            $0.errorMessage = Self.recoveredNote
        }
        return settleTranscript(try? repo.recording(id: row.id), durationMs: duration)
    }

    /// A live transcript that stopped early is finished from the sidecars.
    private func settleTranscript(_ row: RecordingRow?, durationMs: Int64) -> String? {
        guard let row, row.transcriptStatus == .live || row.transcriptStatus == .partial else { return nil }
        let hasAudio = [row.micAudioPath, row.systemAudioPath].compactMap { $0 }.contains { files.exists(URL(fileURLWithPath: $0)) }
        if hasAudio && row.transcribedUntilMs < durationMs - 2_000 {
            try? repo.modify(row.id) { $0.transcriptStatus = .retranscribing }
            return row.id
        }
        try? repo.modify(row.id) { $0.transcriptStatus = hasAudio || row.transcribedUntilMs > 0 ? .complete : .partial }
        return nil
    }

    /// Video files in Staging that the library does not know about.
    private func registerOrphans() async -> [String] {
        let known = (try? repo.knownVideoPaths()) ?? []
        var ids: [String] = []
        let staged = files.list(paths.staging)
        for url in staged where url.pathExtension == "mp4" || url.pathExtension == "mov" {
            let mp4 = url.deletingPathExtension().appendingPathExtension("mp4")
            if known.contains(mp4.path) || known.contains(url.path) { continue }
            if url.pathExtension == "mov" {
                if files.exists(mp4) { continue }
                try? await media.remux(url, to: mp4)
            }
            guard files.exists(mp4), let duration = await media.durationMs(mp4) else { continue }
            let id = UUID().uuidString
            let created = (try? mp4.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let row = RecordingRow(
                id: id, title: RecordingName.timestamp(created), startedAt: created,
                endedAt: created.addingTimeInterval(Double(duration) / 1000), durationMs: duration,
                stagingPath: mp4.path, sizeBytes: files.size(mp4), status: .unsaved,
                transcriptStatus: .retranscribing, errorMessage: Self.recoveredNote)
            // No sidecars survive for orphans, so the transcript comes from
            // the video's mixed audio.
            if (try? repo.insert(row)) != nil { ids.append(id) }
        }
        return ids
    }
}
