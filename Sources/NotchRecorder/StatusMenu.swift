import AppKit

/// The menu bar icon and its menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: AppCoordinator
    var openLibrary: (String?) -> Void = { _ in }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update(recording: false)
    }

    func update(recording: Bool) {
        let name = recording ? "record.circle.fill" : "record.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Notch Recorder")
        if recording {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            item.button?.image = image?.withSymbolConfiguration(config)
            item.button?.image?.isTemplate = false
        } else {
            item.button?.image = image
            item.button?.image?.isTemplate = true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = switch coordinator.phase {
        case .idle: "Start recording"
        case .starting: "Cancel recording"
        case .recording, .paused, .stopping: "Stop recording"
        }
        let toggle = NSMenuItem(title: title, action: #selector(toggle), keyEquivalent: "r")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        toggle.target = self
        toggle.isEnabled = coordinator.phase != .stopping
        menu.autoenablesItems = false
        menu.addItem(toggle)
        if coordinator.isRecording {
            let live = NSMenuItem(title: "Show live transcript", action: #selector(showLive), keyEquivalent: "")
            live.target = self
            menu.addItem(live)
        }
        menu.addItem(.separator())
        let library = NSMenuItem(title: "Open Library", action: #selector(library), keyEquivalent: "")
        library.target = self
        menu.addItem(library)
        let settings = NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Notch Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggle() { coordinator.toggle() }
    @objc private func showLive() { coordinator.showWindow() }
    @objc private func library() { openLibrary(nil) }
    @objc private func settings() { openLibrary("#/settings") }
}
