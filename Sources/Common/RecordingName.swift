import Foundation

/// Filenames match OBS's `%CCYY-%MM-%DD %hh-%mm-%ss` pattern.
public enum RecordingName {
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f.string(from: date)
    }

    /// Makes a user title safe as a filename: no slashes or colons, trimmed,
    /// never empty.
    public static func sanitize(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Recording" : String(cleaned.prefix(200))
    }

    /// First free URL in `folder` for `base.ext`, adding " 2", " 3", ...
    public static func uniqueURL(in folder: URL, base: String, ext: String, exists: (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.path)
    }) -> URL {
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
