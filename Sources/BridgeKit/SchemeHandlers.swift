import Common
import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the built Library UI from the app bundle at `nr-app://app/...`.
public final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "nr-app"
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!)
            task.didFinish()
            return
        }
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-cache",
        ])!)
        task.didReceive(data)
        task.didFinish()
    }

    public func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// Serves recordings and thumbnails with HTTP range support so the video
/// player can seek in multi-gigabyte files without loading them:
/// `nr-media://video/<id>` and `nr-media://thumb/<id>/<n>.jpg`.
public final class MediaSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "nr-media"
    /// Largest single response; players ask again for the rest.
    static let maxChunk: Int64 = 8 * 1024 * 1024

    private let resolve: @Sendable (_ kind: String, _ parts: [String]) -> URL?
    private let lock = NSLock()
    private var stopped = Set<ObjectIdentifier>()
    private let queue = DispatchQueue(label: "media.scheme", qos: .userInitiated, attributes: .concurrent)

    public init(resolve: @escaping @Sendable (_ kind: String, _ parts: [String]) -> URL?) {
        self.resolve = resolve
    }

    public struct ByteRange: Equatable {
        public var start: Int64
        public var end: Int64
    }

    /// Parses `bytes=a-b`, `bytes=a-`, `bytes=-n` against a file size.
    public static func parseRange(_ header: String?, size: Int64) -> ByteRange? {
        guard size > 0 else { return nil }
        guard let header, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let n = Int64(parts[1]) {
            return ByteRange(start: max(0, size - n), end: size - 1)
        }
        guard let start = Int64(parts[0]), start < size else { return nil }
        let end = Int64(parts[1]).map { min($0, size - 1) } ?? size - 1
        return end >= start ? ByteRange(start: start, end: end) : nil
    }

    public func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        let request = task.request
        queue.async { [weak self] in
            guard let self, let url = request.url else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard let host = url.host(), let file = self.resolve(host, parts),
                  let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
                  let handle = try? FileHandle(forReadingFrom: file)
            else {
                self.respond(id, task) { $0.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!); $0.didFinish() }
                return
            }
            defer { try? handle.close() }
            let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let requested = Self.parseRange(request.value(forHTTPHeaderField: "Range"), size: size)
            let range = requested.map { ByteRange(start: $0.start, end: min($0.end, $0.start + Self.maxChunk - 1)) }
                ?? ByteRange(start: 0, end: min(size - 1, Self.maxChunk - 1))
            let isPartial = requested != nil || range.end < size - 1
            do {
                try handle.seek(toOffset: UInt64(range.start))
                let data = try handle.read(upToCount: Int(range.end - range.start + 1)) ?? Data()
                var headers = [
                    "Content-Type": type,
                    "Content-Length": String(data.count),
                    "Accept-Ranges": "bytes",
                    "Cache-Control": "no-cache",
                ]
                if isPartial { headers["Content-Range"] = "bytes \(range.start)-\(range.start + Int64(data.count) - 1)/\(size)" }
                let response = HTTPURLResponse(url: url, statusCode: isPartial ? 206 : 200, httpVersion: "HTTP/1.1", headerFields: headers)!
                self.respond(id, task) { t in
                    t.didReceive(response)
                    t.didReceive(data)
                    t.didFinish()
                }
            } catch {
                self.respond(id, task) { $0.didFailWithError(error) }
            }
        }
    }

    public func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        lock.lock()
        stopped.insert(ObjectIdentifier(task))
        lock.unlock()
    }

    /// Calling a stopped task throws an Objective-C exception, so check first
    /// (on the main thread, where WebKit expects it).
    private func respond(_ id: ObjectIdentifier, _ task: any WKURLSchemeTask, _ body: @escaping (any WKURLSchemeTask) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isStopped = self.stopped.remove(id) != nil
            self.lock.unlock()
            if !isStopped { body(task) }
        }
    }
}
