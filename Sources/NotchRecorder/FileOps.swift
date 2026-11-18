import Foundation

/// File operations behind a protocol so save and recovery logic is testable.
protocol FileOps: Sendable {
    func exists(_ url: URL) -> Bool
    func move(_ from: URL, to: URL) throws
    func createFolder(_ url: URL) throws
    func trash(_ url: URL) throws
    func remove(_ url: URL)
    func write(_ text: String, to url: URL) throws
    func size(_ url: URL) -> Int64
    func list(_ folder: URL) -> [URL]
}

struct LiveFileOps: FileOps {
    var fm: FileManager { .default }
    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
    /// Renames on the same volume; copies then deletes across volumes.
    func move(_ from: URL, to: URL) throws { try fm.moveItem(at: from, to: to) }
    func createFolder(_ url: URL) throws { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
    func trash(_ url: URL) throws { try fm.trashItem(at: url, resultingItemURL: nil) }
    func remove(_ url: URL) { try? fm.removeItem(at: url) }
    func write(_ text: String, to url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
    func size(_ url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    func list(_ folder: URL) -> [URL] { (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] }
}
