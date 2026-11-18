import AppKit
import SwiftUI

/// The live transcript window. It floats above other windows without taking
/// focus when a recording starts, and is excluded from the capture along with
/// the rest of the app. Its close button only works once nothing is running:
/// a recording ends with Stop, never by closing the window.
@MainActor
public final class LiveWindowController: NSObject, NSWindowDelegate {
    public let model: LiveModel
    private var panel: NSPanel?

    public init(model: LiveModel) {
        self.model = model
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the window for the current phase (creating it on first use).
    public func show() {
        let p = panel ?? makePanel()
        panel = p
        p.standardWindowButton(.closeButton)?.isEnabled = !model.isActive
        if !p.isVisible { p.orderFrontRegardless() }
    }

    /// Brings the window forward and focuses it (menu bar command).
    public func focus() {
        guard model.phase != .hidden else { return }
        show()
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        model.phase = .hidden
        panel?.orderOut(nil)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.isActive else { return false }
        hide()
        return false
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.title = "Live transcript"
        p.titlebarAppearsTransparent = true
        p.backgroundColor = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.094, alpha: 1)
        p.appearance = NSAppearance(named: .darkAqua)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 380, height: 240)
        p.delegate = self
        p.contentView = NSHostingView(rootView: LiveRootView(model: model))
        p.setFrameAutosaveName("LiveTranscriptWindow")
        if !p.setFrameUsingName("LiveTranscriptWindow"), let screen = NSScreen.main {
            // First run: top right of the main screen.
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - p.frame.width - 24, y: v.maxY - p.frame.height - 24))
        }
        return p
    }
}
