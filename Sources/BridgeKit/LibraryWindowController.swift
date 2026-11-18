import AppKit
import Common
import WebKit

/// The Library window: a WKWebView hosting the TypeScript UI. Created when
/// opened and fully torn down when closed, so WebKit's helper processes
/// exit and the app goes back to its idle footprint.
@MainActor
public final class LibraryWindowController: NSObject, NSWindowDelegate, WKScriptMessageHandlerWithReply, WKScriptMessageHandler, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: LibraryWebView?
    private let router: BridgeRouter
    private let webRoot: URL
    private let media: MediaSchemeHandler
    private var ready = false
    private var queued: [String] = []
    public var onClose: (() -> Void)?
    public var onOpen: (() -> Void)?

    public init(router: BridgeRouter, webRoot: URL, media: MediaSchemeHandler) {
        self.router = router
        self.webRoot = webRoot
        self.media = media
    }

    public var isOpen: Bool { window != nil }

    /// Opens (or focuses) the window, optionally at a route such as
    /// `#/recording/<id>`.
    public func show(route: String? = nil) {
        if let window {
            if let route { navigate(route) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AppSchemeHandler(root: webRoot), forURLScheme: AppSchemeHandler.scheme)
        config.setURLSchemeHandler(media, forURLScheme: MediaSchemeHandler.scheme)
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bridge")
        config.userContentController.add(self, contentWorld: .page, name: "chrome")
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = LibraryWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        web.isInspectable = true
        #endif

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = "Notch Recorder"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.minSize = NSSize(width: 880, height: 560)
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.094, alpha: 1)
        w.contentView = web
        w.delegate = self
        w.setFrameAutosaveName("LibraryWindow")
        if !w.setFrameUsingName("LibraryWindow") { w.center() }
        window = w
        webView = web
        ready = false
        let start = URL(string: "\(AppSchemeHandler.scheme)://app/index.html\(route ?? "")")!
        web.load(URLRequest(url: start))
        onOpen?()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public func close() {
        window?.close()
    }

    public func navigate(_ route: String) {
        run("window.location.hash = \(jsString(route.hasPrefix("#") ? String(route.dropFirst()) : route))")
    }

    /// Pushes an event to the page (dropped when the window is closed).
    public func send(_ event: BridgeEvent) {
        guard webView != nil, let data = try? JSONEncoder().encode(event), let json = String(data: data, encoding: .utf8) else { return }
        run("window.__nrEvent && window.__nrEvent(\(json))")
    }

    private func run(_ js: String) {
        guard let webView else { return }
        if ready {
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            queued.append(js)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        for js in queued { webView.evaluateJavaScript(js, completionHandler: nil) }
        queued.removeAll()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // External links open in the browser, never inside the app.
        if let url = action.request.url, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.bridge.error("web content process ended, reloading")
        webView.reload()
    }

    public func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let method = body["method"] as? String else {
            replyHandler(["ok": false, "error": ["code": "InvalidParams", "message": "Malformed request."]], nil)
            return
        }
        let params = body["params"]
        let router = self.router
        nonisolated(unsafe) let unsafeParams = params
        Task {
            let reply = await router.handle(method: method, params: unsafeParams)
            nonisolated(unsafe) let unsafeReply = reply
            await MainActor.run { replyHandler(unsafeReply, nil) }
        }
    }

    /// Title bar behaviour for the page's header regions (see titlebar.ts).
    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "chrome", let window, let action = message.body as? String else { return }
        switch action {
        case "drag":
            if let event = webView?.lastMouseDown { window.performDrag(with: event) }
        case "zoom":
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.miniaturize(nil)
            case "None": break
            default: window.zoom(nil)
            }
        default:
            break
        }
    }

    public func windowWillClose(_ notification: Notification) {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        window?.delegate = nil
        window = nil
        ready = false
        queued.removeAll()
        onClose?()
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let arr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }
}

/// Remembers the mouse-down that a title bar drag starts from.
final class LibraryWebView: WKWebView {
    private(set) var lastMouseDown: NSEvent?

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }
}
