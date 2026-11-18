import Foundation

/// Every location the app writes to. All live under one Application Support
/// folder so Time Machine picks them up and nothing leaks elsewhere.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static let live = AppPaths(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchRecorder", isDirectory: true))

    public var database: URL { root.appendingPathComponent("library.sqlite") }
    public var staging: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    public var audio: URL { root.appendingPathComponent("Audio", isDirectory: true) }
    public var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    public var models: URL { root.appendingPathComponent("Models", isDirectory: true) }
    public var stateFile: URL { root.appendingPathComponent("state.json") }

    public func thumbnailDirectory(for id: String) -> URL {
        thumbnails.appendingPathComponent(id, isDirectory: true)
    }

    public func ensureDirectories() throws {
        for dir in [root, staging, audio, thumbnails, models] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Where saved videos go until the user picks another folder in
    /// Settings: `~/Movies/Notch Recorder`. Created on the first save.
    public static var defaultVideoFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Notch Recorder", isDirectory: true)
    }
}
