import AppKit
import BridgeKit
import Common
import Foundation
import LibraryKit
import TranscriptKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var library: LibraryWindowController!
    private var statusMenu: StatusMenu!
    private var hotKey: HotKey?
    private var jobs: JobQueue!
    private var repo: LibraryRepository!
    /// Handles every Library request; the router only holds it unowned.
    private var service: LibraryService!
    private var observers: [NSObjectProtocol] = []
    private let paths = AppPaths.live

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try paths.ensureDirectories()
            repo = LibraryRepository(db: try LibraryDatabase.open(at: paths.database))
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't open the Library"
            alert.informativeText = "\(error.localizedDescription)\n\nThe library is at \(paths.database.path)."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let settings = SettingsStore(repo: repo)
        let formatter = Bundle.main.url(forResource: "core.jsc", withExtension: "js").map(TranscriptFormatter.init(script:))
        let saver = SaveService(repo: repo, paths: paths, files: LiveFileOps(), formatter: formatter)
        jobs = JobQueue(repo: repo, makeEngine: { FluidSpeechEngine() })
        coordinator = AppCoordinator(paths: paths, repo: repo, settings: settings, jobs: jobs, saver: saver)

        let router = BridgeRouter()
        let repo = self.repo!
        let paths = self.paths
        let media = MediaSchemeHandler { kind, parts in
            switch kind {
            case "video":
                guard let id = parts.first, let row = try? repo.recording(id: id), let p = row.currentVideoPath else { return nil }
                return URL(fileURLWithPath: p)
            case "thumb":
                guard parts.count == 2 else { return nil }
                return paths.thumbnailDirectory(for: parts[0]).appendingPathComponent(parts[1])
            default:
                return nil
            }
        }
        let webRoot = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
        library = LibraryWindowController(router: router, webRoot: webRoot, media: media)
        library.onOpen = { NSApp.setActivationPolicy(.regular) }
        library.onClose = { NSApp.setActivationPolicy(.accessory) }
        service = LibraryService(repo: repo, coordinator: coordinator, jobs: jobs, saver: saver, settings: settings)
        service.register(on: router)

        coordinator.publish = { [weak self] event in self?.library.send(event) }
        jobs.publish = { [weak self] event in self?.library.send(event) }
        coordinator.openLibrary = { [weak self] route in self?.library.show(route: route) }

        statusMenu = StatusMenu(coordinator: coordinator)
        statusMenu.openLibrary = { [weak self] route in self?.library.show(route: route) }
        coordinator.onPhaseChange = { [weak self] phase in self?.statusMenu.update(recording: phase != .idle) }

        hotKey = HotKey { [weak self] in
            DispatchQueue.main.async { self?.coordinator.toggle() }
        }
        observeSystem()
        settings.applyLaunchAtLogin()

        // Finish anything a crash or forced quit left behind.
        let recovery = Recovery(repo: repo, paths: paths, files: LiveFileOps(), media: LiveRecoveryMedia())
        Task {
            let ids = await recovery.run()
            for id in ids { jobs.enqueue(id) }
            if !ids.isEmpty { Log.app.info("recovery queued \(ids.count) transcripts") }
        }

        if !Permissions.screen || Permissions.microphone == .notDetermined {
            library.show(route: "#/onboarding")
        }
        Log.app.info("launched")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        library.show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        let policy = TerminationPolicy.decide(
            isRecording: coordinator.isRecording, hasJob: jobs.isRunning, systemIsShuttingDown: Self.systemIsShuttingDown())
        switch policy {
        case .now:
            return .terminateNow
        case .ask:
            let alert = NSAlert()
            alert.messageText = "Stop recording and quit?"
            alert.informativeText = "The recording and its transcript are kept as unsaved in the Library."
            alert.addButton(withTitle: "Stop and quit")
            alert.addButton(withTitle: "Keep recording")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            fallthrough
        case .stopThenQuit:
            Task {
                await coordinator.prepareForTermination()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    /// True when the quit comes from logout, restart or shutdown.
    private static func systemIsShuttingDown() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let reason = event.attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue
        else { return false }
        return [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown]
            .map { OSType($0) }.contains(reason)
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.coordinator.systemWillSleep() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.coordinator.systemDidWake() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.coordinator.prepareForTermination() }
        })
    }

    /// notchrecorder://start | stop | toggle | library | settings | close
    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string), url.scheme == "notchrecorder" else { return }
        switch url.host() {
        case "start": Task { await coordinator.start() }
        case "stop": Task { await coordinator.stop() }
        case "toggle": coordinator.toggle()
        case "settings": library.show(route: "#/settings")
        case "close": library.close()
        default: library.show()
        }
    }
}
