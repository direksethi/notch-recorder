import Common
import Foundation
import GRDB

/// All reads and writes to the library. Thread safe (GRDB serialises access).
public final class LibraryRepository: @unchecked Sendable {
    public let db: DatabaseQueue
    private let fileExists: @Sendable (String) -> Bool

    public init(
        db: DatabaseQueue,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.db = db
        self.fileExists = fileExists
    }

    // MARK: Recordings

    public func insert(_ recording: RecordingRow) throws {
        try wrap { try db.write { try recording.insert($0) } }
    }

    public func update(_ recording: RecordingRow) throws {
        try wrap { try db.write { try recording.update($0) } }
    }

    /// Reads, changes and writes one recording in a single transaction.
    @discardableResult
    public func modify(_ id: String, _ change: (inout RecordingRow) -> Void) throws -> RecordingRow {
        try wrap {
            try db.write { db in
                guard var row = try RecordingRow.fetchOne(db, key: id) else { throw LibraryError.notFound(id) }
                change(&row)
                try row.update(db)
                return row
            }
        }
    }

    public func recording(id: String) throws -> RecordingRow {
        guard let row = try wrap({ try db.read { try RecordingRow.fetchOne($0, key: id) } }) else {
            throw LibraryError.notFound(id)
        }
        return row
    }

    /// Everything except discarded recordings, newest first.
    public func listRecordings() throws -> [RecordingSummary] {
        let rows: [(RecordingRow, String?, String?, Int)] = try wrap {
            try db.read { db in
                let recordings = try RecordingRow
                    .filter(Column("status") != RecordingStatus.discarded.rawValue)
                    .order(Column("startedAt").desc)
                    .fetchAll(db)
                return try recordings.map { r in
                    let first = try Row.fetchOne(
                        db,
                        sql: "SELECT text, source FROM segment WHERE recordingId = ? ORDER BY startMs LIMIT 1",
                        arguments: [r.id])
                    let count = try Int.fetchOne(
                        db, sql: "SELECT COUNT(*) FROM segment WHERE recordingId = ?", arguments: [r.id]) ?? 0
                    return (r, first?["text"], first?["source"], count)
                }
            }
        }
        return rows.map { r, preview, source, count in
            RecordingSummary(
                recording: r,
                preview: preview,
                previewSource: source.flatMap(AudioSource.init(rawValue:)),
                segmentCount: count,
                fileMissing: isFileMissing(r))
        }
    }

    public func isFileMissing(_ r: RecordingRow) -> Bool {
        guard r.status != .recording else { return false }
        guard let path = r.currentVideoPath else { return true }
        return !fileExists(path)
    }

    /// Recordings that were still recording when the app last stopped, or
    /// whose transcript was interrupted.
    public func unfinishedRecordings() throws -> [RecordingRow] {
        try wrap {
            try db.read { db in
                try RecordingRow
                    .filter(
                        Column("status") == RecordingStatus.recording.rawValue
                            || Column("transcriptStatus") == TranscriptStatus.retranscribing.rawValue
                            || Column("transcriptStatus") == TranscriptStatus.live.rawValue)
                    .fetchAll(db)
            }
        }
    }

    public func delete(id: String) throws {
        try wrap { _ = try db.write { try RecordingRow.deleteOne($0, key: id) } }
    }

    public func knownVideoPaths() throws -> Set<String> {
        try wrap {
            try db.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT stagingPath, videoPath FROM recording")
                var paths = Set<String>()
                for row in rows {
                    if let p: String = row["stagingPath"] { paths.insert(p) }
                    if let p: String = row["videoPath"] { paths.insert(p) }
                }
                return paths
            }
        }
    }

    // MARK: Segments

    @discardableResult
    public func appendSegment(_ segment: SegmentRow) throws -> SegmentRow {
        try wrap {
            try db.write { db in
                var s = segment
                try s.insert(db)
                try db.execute(
                    sql: "UPDATE recording SET transcribedUntilMs = MAX(transcribedUntilMs, ?) WHERE id = ?",
                    arguments: [s.endMs, s.recordingId])
                return s
            }
        }
    }

    public func segments(recordingId: String) throws -> [SegmentRow] {
        try wrap {
            try db.read { db in
                try SegmentRow
                    .filter(Column("recordingId") == recordingId)
                    .order(Column("startMs"), Column("id"))
                    .fetchAll(db)
            }
        }
    }

    /// Replaces every segment starting at or after `fromMs` with `segments`.
    public func replaceSegments(recordingId: String, fromMs: Int64, with segments: [SegmentRow]) throws {
        try wrap {
            try db.write { db in
                try db.execute(
                    sql: "DELETE FROM segment WHERE recordingId = ? AND startMs >= ?",
                    arguments: [recordingId, fromMs])
                for var s in segments { try s.insert(db) }
            }
        }
    }

    /// Changes a segment's text, keeping the first original.
    @discardableResult
    public func editSegment(id: Int64, text: String) throws -> SegmentRow {
        try wrap {
            try db.write { db in
                guard var s = try SegmentRow.fetchOne(db, key: id) else {
                    throw LibraryError.notFound(String(id))
                }
                if s.originalText == nil, s.text != text { s.originalText = s.text }
                s.text = text
                try s.update(db)
                return s
            }
        }
    }

    // MARK: Search

    public func search(query: String, source: AudioSource? = nil, limit: Int = 300) throws -> [SearchHit] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        return try wrap {
            try db.read { db in
                var sql = """
                    SELECT s.id AS segmentId, s.recordingId, s.source, s.startMs,
                           highlight(segment_fts, 0, char(1), char(2)) AS highlighted,
                           r.title, r.startedAt, r.durationMs
                    FROM segment_fts
                    JOIN segment s ON s.id = segment_fts.rowid
                    JOIN recording r ON r.id = s.recordingId
                    WHERE segment_fts MATCH ? AND r.status != 'discarded'
                    """
                var args: [any DatabaseValueConvertible] = [pattern]
                if let source {
                    sql += " AND s.source = ?"
                    args.append(source.rawValue)
                }
                sql += " ORDER BY r.startedAt DESC, s.startMs LIMIT ?"
                args.append(limit)
                return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
                    SearchHit(
                        recordingId: row["recordingId"],
                        recordingTitle: row["title"],
                        startedAt: row["startedAt"],
                        durationMs: row["durationMs"],
                        segmentId: row["segmentId"],
                        source: AudioSource(rawValue: row["source"]) ?? .speaker,
                        startMs: row["startMs"],
                        highlighted: row["highlighted"])
                }
            }
        }
    }

    // MARK: Settings

    public func setting(_ key: String) throws -> String? {
        try wrap { try db.read { try String.fetchOne($0, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) } }
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try wrap {
            try db.write {
                try $0.execute(
                    sql: "INSERT INTO setting(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    arguments: [key, value])
            }
        }
    }

    // MARK: Errors

    private func wrap<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let e as LibraryError {
            throw e
        } catch {
            Log.library.error("database error: \(String(describing: error), privacy: .public)")
            throw LibraryError.database(String(describing: error))
        }
    }
}
