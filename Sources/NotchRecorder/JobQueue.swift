import BridgeKit
import Common
import Foundation
import LibraryKit
import TranscriptKit

/// Runs "transcribe again" jobs one at a time, only while nothing is being
/// recorded (so a recording never competes with them). Progress is kept in
/// the database: an interrupted job starts again from `transcribedUntilMs`
/// on next launch.
@MainActor
final class JobQueue {
    private let repo: LibraryRepository
    private let makeEngine: () -> SpeechEngine
    private var pending: [String] = []
    private var running: (id: String, task: Task<Void, Never>)?
    private var paused = false
    var publish: (BridgeEvent) -> Void = { _ in }
    var afterJob: (String) -> Void = { _ in }

    init(repo: LibraryRepository, makeEngine: @escaping () -> SpeechEngine) {
        self.repo = repo
        self.makeEngine = makeEngine
    }

    var isRunning: Bool { running != nil }

    func enqueue(_ id: String) {
        guard running?.id != id, !pending.contains(id) else { return }
        pending.append(id)
        next()
    }

    /// Recording started: stop the current job (it resumes later).
    func pause() {
        paused = true
        if let r = running {
            pending.insert(r.id, at: 0)
            r.task.cancel()
        }
    }

    func resume() {
        paused = false
        next()
    }

    /// Cancelled by the user: the transcript stays as it was.
    func cancel(_ id: String) {
        pending.removeAll { $0 == id }
        if running?.id == id { running?.task.cancel() }
        try? repo.modify(id) { if $0.transcriptStatus == .retranscribing { $0.transcriptStatus = .complete } }
        publish(.libraryChanged(recordingId: id))
    }

    /// App quitting: stop without touching the database so it resumes.
    func stopForQuit() async {
        pending.removeAll()
        if let r = running {
            r.task.cancel()
            await r.task.value
        }
    }

    private func next() {
        guard !paused, running == nil, !pending.isEmpty else { return }
        let id = pending.removeFirst()
        let task = Task { [weak self] in
            await self?.run(id)
            guard let self else { return }
            self.running = nil
            self.afterJob(id)
            self.next()
        }
        running = (id, task)
    }

    private func run(_ id: String) async {
        guard let row = try? repo.recording(id: id) else { return }
        try? repo.modify(id) { $0.transcriptStatus = .retranscribing }
        publish(.libraryChanged(recordingId: id))
        let input = Retranscriber.Input(
            micAudio: row.micAudioPath.map(URL.init(fileURLWithPath:)),
            systemAudio: row.systemAudioPath.map(URL.init(fileURLWithPath:)),
            video: row.currentVideoPath.map(URL.init(fileURLWithPath:)),
            fromMs: row.transcribedUntilMs, durationMs: row.durationMs)
        let publish = self.publish
        do {
            let drafts = try await Retranscriber(engine: makeEngine()).run(input) { fraction in
                Task { @MainActor in publish(.retranscribeProgress(recordingId: id, fraction: fraction)) }
            }
            try Task.checkCancellation()
            try repo.replaceSegments(recordingId: id, fromMs: input.fromMs, with: drafts.map {
                SegmentRow(recordingId: id, source: $0.source, startMs: $0.startMs, endMs: $0.endMs, text: $0.text, confidence: $0.confidence)
            })
            try repo.modify(id) {
                $0.transcriptStatus = .complete
                $0.transcribedUntilMs = max($0.durationMs, $0.transcribedUntilMs)
            }
            publish(.notice(level: "info", message: "Transcript ready: \(row.title)."))
        } catch is CancellationError {
            Log.transcript.info("job \(id, privacy: .public) paused")
        } catch {
            Log.transcript.error("job \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            try? repo.modify(id) { $0.transcriptStatus = .failed }
            publish(.notice(level: "error", message: "Couldn't transcribe \(row.title). \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"))
        }
        publish(.libraryChanged(recordingId: id))
    }
}
