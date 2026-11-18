import AppKit
import BridgeKit
import Common
import Foundation
import LibraryKit
import LiveUI
import RecorderKit
import TranscriptKit

/// Owns the recording lifecycle: load the speech model, record with a live
/// transcript window, stop and save automatically, sleep and wake, and a
/// clean stop when the app quits.
@MainActor
final class AppCoordinator {
    enum Phase: String {
        case idle, starting, recording, paused, stopping
    }

    private struct Active {
        let id: String
        let session: RecordingSession
        let transcriber: LiveTranscriber?
        var consumer: Task<Void, Never>?
        var speechTask: Task<Void, Never>?
        let startedAt: Date
    }

    let paths: AppPaths
    let repo: LibraryRepository
    let settings: SettingsStore
    let jobs: JobQueue
    let saver: SaveService
    let window: LiveWindowController
    var model: LiveModel { window.model }
    var publish: (BridgeEvent) -> Void = { _ in }
    var openLibrary: (String?) -> Void = { _ in }
    var onPhaseChange: (Phase) -> Void = { _ in }

    private(set) var phase: Phase = .idle {
        didSet {
            stateFile.write(state: phase.rawValue, recordingId: active?.id)
            publish(.recorderStateChanged(stateDTO))
            onPhaseChange(phase)
        }
    }
    private var active: Active?
    /// Set when the user cancels while the speech model is still loading.
    private var startCancelled = false
    private let stateFile: StateFile
    private let speechEngine = FluidSpeechEngine()

    init(paths: AppPaths, repo: LibraryRepository, settings: SettingsStore, jobs: JobQueue, saver: SaveService) {
        self.paths = paths
        self.repo = repo
        self.settings = settings
        self.jobs = jobs
        self.saver = saver
        stateFile = StateFile(url: paths.stateFile)
        window = LiveWindowController(model: LiveModel())
        stateFile.write(state: "idle", recordingId: nil)
        wireWindow()
    }

    var isRecording: Bool { phase != .idle }

    var stateDTO: RecorderStateDTO {
        RecorderStateDTO(
            phase: phase.rawValue, recordingId: active?.id,
            startedAt: active.map { ($0.startedAt.timeIntervalSince1970 * 1000).rounded() })
    }

    // MARK: Start

    func toggle() {
        Task {
            switch phase {
            case .idle: await start()
            case .starting: cancelStart()
            case .recording, .paused: await stop()
            case .stopping: break
            }
        }
    }

    /// Loads the speech model first, then starts capture, so the transcript
    /// covers the recording from its first second.
    func start() async {
        guard phase == .idle else { return }
        guard Permissions.screen else {
            Permissions.requestScreen()
            openLibrary("#/onboarding")
            return
        }
        let micAllowed = await Permissions.requestMicrophone()
        let s = settings.current
        phase = .starting
        startCancelled = false
        jobs.pause()
        model.reset()
        model.showPartials = s.showPartials
        let id = UUID().uuidString

        var transcriber: LiveTranscriber?
        if s.transcription {
            model.phase = .preparing
            window.show()
            let t = makeTranscriber(id: id, partials: s.showPartials)
            await t.start()
            if case .failed(let message) = await t.currentStatus {
                await t.finish()
                model.transcriptNote = message
            } else {
                transcriber = t
            }
        } else {
            model.transcriptNote = "Live transcription is off. Turn it on in Settings."
        }
        if startCancelled {
            await transcriber?.finish()
            window.hide()
            phase = .idle
            jobs.resume()
            return
        }

        let video = paths.staging.appendingPathComponent("\(id).mp4")
        let mic = paths.audio.appendingPathComponent("\(id)-mic.caf")
        let system = paths.audio.appendingPathComponent("\(id)-system.caf")
        let recordingSettings = settings.recordingSettings(captureMic: micAllowed)
        let now = Date()
        let row = RecordingRow(
            id: id, title: RecordingName.timestamp(now), startedAt: now,
            stagingPath: video.path, status: .recording,
            transcriptStatus: transcriber != nil ? .live : .none,
            micAudioPath: micAllowed ? mic.path : nil, systemAudioPath: system.path,
            settingsJSON: (try? String(data: JSONEncoder().encode(recordingSettings), encoding: .utf8) ?? "{}") ?? "{}")
        do {
            try repo.insert(row)
        } catch {
            await transcriber?.finish()
            fail("Couldn't create the recording: \(error.localizedDescription)")
            return
        }

        let session = RecordingSession(
            id: id, settings: recordingSettings,
            paths: .init(video: video, micAudio: mic, systemAudio: system),
            source: CaptureSource(settings: recordingSettings))
        do {
            try await session.start()
        } catch {
            await transcriber?.finish()
            try? repo.delete(id: id)
            for url in [video, MovieWriter.workingURL(for: video), mic, system] { try? FileManager.default.removeItem(at: url) }
            fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }

        if !micAllowed { model.warning = "Microphone access is off. Only system audio is being recorded." }
        var a = Active(id: id, session: session, transcriber: transcriber, startedAt: now)
        let (speech, speechIn) = AsyncStream.makeStream(of: (AudioSource, [Float], Int64).self)
        if let transcriber {
            a.speechTask = Task.detached(priority: .userInitiated) {
                for await (source, samples, start) in speech {
                    await transcriber.feed(source: source, samples: samples, startSample: start)
                }
            }
        }
        a.consumer = Task { [weak self] in
            for await event in session.events {
                guard let self else { break }
                switch event {
                case .speech(let source, let samples, let start):
                    if transcriber != nil { speechIn.yield((source, samples, start)) }
                case .levels(let me, let others):
                    self.model.meLevel = me
                    self.model.othersLevel = others
                case .elapsed(let t):
                    self.model.elapsed = t
                case .warning(let w):
                    self.model.warning = w
                case .state(let state):
                    self.handle(state, id: id)
                }
            }
            speechIn.finish()
        }
        active = a
        phase = .recording
        model.phase = .recording
        window.show()
        publish(.libraryChanged(recordingId: id))
        Log.app.info("recording started \(id, privacy: .public)")
    }

    /// Cancels a start that is still waiting for the speech model.
    func cancelStart() {
        guard phase == .starting, model.phase == .preparing else { return }
        startCancelled = true
        window.hide()
    }

    private func makeTranscriber(id: String, partials: Bool) -> LiveTranscriber {
        LiveTranscriber(
            engine: speechEngine, partials: partials,
            onPartial: { [weak self] source, text in
                Task { @MainActor in self?.model.setPartial(source, text) }
            },
            onFinal: { [weak self] draft in
                Task { @MainActor in self?.handleFinal(id: id, draft) }
            },
            onStatus: { [weak self] status in
                Task { @MainActor in self?.handleTranscriber(status) }
            })
    }

    private func handleFinal(id: String, _ d: SegmentDraft) {
        do {
            let row = try repo.appendSegment(SegmentRow(
                recordingId: id, source: d.source, startMs: d.startMs, endMs: d.endMs, text: d.text, confidence: d.confidence))
            publish(.segmentAdded(recordingId: id, segment: SegmentDTO(row)))
        } catch {
            Log.app.error("could not store segment: \(error.localizedDescription, privacy: .public)")
        }
        if active?.id == id { model.addFinal(d.source, d.text) }
    }

    private func handleTranscriber(_ status: TranscriberStatus) {
        switch status {
        case .failed(let m): model.transcriptNote = m
        case .loading, .running, .finished: break
        }
    }

    /// Session state changes that come from the recorder itself (errors).
    private func handle(_ state: SessionState, id: String) {
        switch state {
        case .paused:
            if phase == .recording { phase = .paused }
            model.phase = .paused
        case .recording:
            if phase == .paused { phase = .recording }
            model.phase = .recording
        case .failed(let error, _) where phase == .recording || phase == .paused:
            // The recorder stopped on its own (disk full, display gone).
            model.warning = error.localizedDescription
            Task { await self.finish(id: id, error: error) }
        default:
            break
        }
    }

    // MARK: Stop

    func stop() async {
        guard let a = active, phase == .recording || phase == .paused else { return }
        phase = .stopping
        model.phase = .finishing
        window.show()
        _ = await a.session.stop()
        await finish(id: a.id, error: nil)
    }

    /// Finalises bookkeeping after the session has stopped (by request or by
    /// error), then saves to the video folder. The window closes on a clean
    /// save and stays open only to explain a problem. `quitting` skips the
    /// save: the recording is kept as Unsaved and recovered on next launch.
    private func finish(id: String, error: RecorderError?, quitting: Bool = false) async {
        guard let a = active, a.id == id else { return }
        active = nil
        if phase != .stopping { phase = .stopping }
        model.phase = .finishing
        await a.consumer?.value
        await a.speechTask?.value
        var transcriptStatus: TranscriptStatus = .none
        if let t = a.transcriber {
            await t.finish()
            switch await t.currentStatus {
            case .failed: transcriptStatus = .failed
            default: transcriptStatus = .complete
            }
        }
        var output: RecordingOutput?
        var finalError = error
        switch a.session.currentState {
        case .finished(let o): output = o
        case .failed(let e, let o):
            output = o
            finalError = finalError ?? e
        default: break
        }
        if let output {
            try? repo.modify(id) {
                $0.status = .unsaved
                $0.durationMs = Int64(output.duration * 1000)
                $0.endedAt = output.startedAt.addingTimeInterval(output.duration)
                $0.width = output.width
                $0.height = output.height
                $0.displayName = output.displayName
                $0.sizeBytes = output.sizeBytes
                $0.transcriptStatus = transcriptStatus
                $0.micAudioPath = output.micAudioURL?.path
                $0.systemAudioPath = output.systemAudioURL?.path
                $0.errorMessage = finalError?.localizedDescription
            }
            makeThumbnails(id: id, video: output.videoURL)
        } else {
            if let row = try? repo.recording(id: id) { saver.removeArtifacts(of: row, video: true) }
            try? repo.delete(id: id)
        }

        if quitting {
            window.hide()
        } else if output == nil {
            showNotice("Recording failed", finalError?.localizedDescription ?? "No video was recorded.")
        } else {
            autoSave(id: id, stoppedBy: finalError)
        }
        phase = .idle
        jobs.resume()
        publish(.libraryChanged(recordingId: id))
        Log.app.info("recording finished \(id, privacy: .public)")
    }

    /// Saves under the recording's date and time to the video folder from
    /// Settings, exporting the transcript when Settings ask for it.
    private func autoSave(id: String, stoppedBy error: RecorderError?) {
        let s = settings.current
        let title = (try? repo.recording(id: id).title) ?? RecordingName.timestamp(Date())
        do {
            let result = try saver.save(
                id: id, title: title, videoFolder: URL(fileURLWithPath: s.videoFolder),
                exportFolder: s.exportOnSave ? URL(fileURLWithPath: s.exportFolder ?? s.videoFolder) : nil,
                exportFormats: s.exportFormats)
            compressSidecars(id: id)
            if let error {
                showNotice("Recording stopped", "\(error.localizedDescription) The recording up to that point was saved as \(result.videoURL.lastPathComponent).")
            } else {
                window.hide()
            }
        } catch {
            showNotice(
                "Couldn't save the recording",
                "\(BridgeFailure.from(error).message) The recording is kept in the Library under Unsaved.")
        }
    }

    private func makeThumbnails(id: String, video: URL) {
        let folder = paths.thumbnailDirectory(for: id)
        let repo = self.repo
        Task.detached(priority: .utility) {
            let count = await Thumbnailer.make(video: video, folder: folder)
            try? repo.modify(id) { $0.thumbnailCount = count }
            await MainActor.run { self.publish(.libraryChanged(recordingId: id)) }
        }
    }

    // MARK: Discard

    func discard(id: String) async {
        if let a = active, a.id == id {
            phase = .stopping
            _ = await a.session.stop()
            await finish(id: a.id, error: nil, quitting: true)
        }
        if let row = try? repo.recording(id: id) {
            saver.removeArtifacts(of: row, video: row.status != .saved)
        }
        try? repo.delete(id: id)
        publish(.libraryChanged(recordingId: id))
    }

    private func compressSidecars(id: String) {
        guard let row = try? repo.recording(id: id) else { return }
        let repo = self.repo
        Task.detached(priority: .background) {
            var mic = row.micAudioPath
            var system = row.systemAudioPath
            if let m = mic, m.hasSuffix(".caf"), let out = try? await SidecarWriter.compress(URL(fileURLWithPath: m)) { mic = out.path }
            if let s = system, s.hasSuffix(".caf"), let out = try? await SidecarWriter.compress(URL(fileURLWithPath: s)) { system = out.path }
            try? repo.modify(id) {
                $0.micAudioPath = mic
                $0.systemAudioPath = system
            }
        }
    }

    // MARK: Window

    private func wireWindow() {
        model.onStop = { [weak self] in Task { await self?.stop() } }
        model.onCancel = { [weak self] in self?.cancelStart() }
        model.onOpenLibrary = { [weak self] in
            self?.window.hide()
            self?.openLibrary(nil)
        }
        model.onClose = { [weak self] in self?.window.hide() }
    }

    /// Shows the live transcript window if a recording is in progress.
    func showWindow() {
        window.focus()
    }

    private func showNotice(_ title: String, _ message: String) {
        model.phase = .notice(title: title, message: message)
        window.show()
    }

    private func fail(_ message: String) {
        phase = .idle
        jobs.resume()
        Log.app.error("start failed: \(message, privacy: .public)")
        showNotice("Couldn't start recording", message)
    }

    // MARK: System events

    func systemWillSleep() async {
        guard let a = active, phase == .recording else { return }
        await a.session.pause()
    }

    func systemDidWake() async {
        guard let a = active, phase == .paused else { return }
        await a.session.resume()
    }

    /// Quit, logout or shutdown: stop and keep the recording as Unsaved.
    func prepareForTermination() async {
        if phase == .starting { cancelStart() }
        if let a = active {
            if phase == .recording || phase == .paused || phase == .starting {
                phase = .stopping
                _ = await a.session.stop()
            }
            await finish(id: a.id, error: nil, quitting: true)
        }
        await jobs.stopForQuit()
        stateFile.write(state: "idle", recordingId: nil)
    }
}

enum Dialogs {
    @MainActor
    static func chooseFolder(initial: String?, prompt: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt ?? "Choose"
        if let initial { panel.directoryURL = URL(fileURLWithPath: initial) }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
