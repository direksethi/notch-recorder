import Foundation
import GRDB

public enum LibraryDatabase {
    /// Opens (and migrates) the library at `url`, or in memory when nil.
    public static func open(at url: URL?) throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue: DatabaseQueue
        if let url {
            queue = try DatabaseQueue(path: url.path, configuration: config)
            try queue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
        } else {
            queue = try DatabaseQueue(configuration: config)
        }
        try migrator.migrate(queue)
        return queue
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "recording") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("durationMs", .integer).notNull().defaults(to: 0)
                t.column("displayName", .text).notNull().defaults(to: "")
                t.column("width", .integer).notNull().defaults(to: 0)
                t.column("height", .integer).notNull().defaults(to: 0)
                t.column("stagingPath", .text)
                t.column("videoPath", .text)
                t.column("sizeBytes", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("transcriptStatus", .text).notNull()
                t.column("transcribedUntilMs", .integer).notNull().defaults(to: 0)
                t.column("micAudioPath", .text)
                t.column("systemAudioPath", .text)
                t.column("thumbnailCount", .integer).notNull().defaults(to: 0)
                t.column("settingsJSON", .text).notNull().defaults(to: "{}")
                t.column("errorMessage", .text)
            }
            try db.create(table: "segment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingId", .text).notNull()
                    .references("recording", onDelete: .cascade)
                t.column("source", .text).notNull()
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("originalText", .text)
                t.column("confidence", .double).notNull().defaults(to: 1)
            }
            try db.create(index: "segment_by_recording", on: "segment", columns: ["recordingId", "startMs"])
            try db.create(virtualTable: "segment_fts", using: FTS5()) { t in
                t.synchronize(withTable: "segment")
                t.tokenizer = .unicode61()
                t.column("text")
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return m
    }
}
