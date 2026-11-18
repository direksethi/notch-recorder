import Common
import Foundation

/// Everything in Settings. Stored as one JSON value in the library database;
/// mirrors `Settings` in web/packages/core/src/contract.ts. Missing keys fall
/// back to the defaults, so older settings always load.
public struct AppSettings: Codable, Sendable, Equatable {
    public var videoFolder: String = AppPaths.defaultVideoFolder.path
    public var exportOnSave = false
    public var exportFolder: String?
    public var exportFormats: [String] = ["md", "srt"]
    public var copyFormat = "clean"
    public var displayId: UInt32?
    public var micDeviceId: String?
    public var showCursor = true
    public var scale = 0.8
    public var retinaPointScale = 4.0 / 3.0
    public var fps = 30
    public var quality = 0.6
    public var transcription = true
    public var showPartials = true
    public var launchAtLogin = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        videoFolder = try c.decodeIfPresent(String.self, forKey: .videoFolder) ?? d.videoFolder
        exportOnSave = try c.decodeIfPresent(Bool.self, forKey: .exportOnSave) ?? d.exportOnSave
        exportFolder = try c.decodeIfPresent(String.self, forKey: .exportFolder)
        exportFormats = try c.decodeIfPresent([String].self, forKey: .exportFormats) ?? d.exportFormats
        copyFormat = try c.decodeIfPresent(String.self, forKey: .copyFormat) ?? d.copyFormat
        displayId = try c.decodeIfPresent(UInt32.self, forKey: .displayId)
        micDeviceId = try c.decodeIfPresent(String.self, forKey: .micDeviceId)
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? d.showCursor
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        retinaPointScale = try c.decodeIfPresent(Double.self, forKey: .retinaPointScale) ?? d.retinaPointScale
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? d.quality
        transcription = try c.decodeIfPresent(Bool.self, forKey: .transcription) ?? d.transcription
        showPartials = try c.decodeIfPresent(Bool.self, forKey: .showPartials) ?? d.showPartials
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }

    /// Applies a partial update (only the keys present in `patch`).
    public func merging(_ patch: [String: Any]) throws -> AppSettings {
        var base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] ?? [:]
        for (k, v) in patch { base[k] = v }
        return try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: base))
    }

    /// Keeps values in sensible ranges.
    public var validated: AppSettings {
        var s = self
        s.scale = min(1, max(0.25, scale))
        s.retinaPointScale = min(2, max(0.5, retinaPointScale))
        s.fps = [24, 25, 30, 50, 60].contains(fps) ? fps : 30
        s.quality = min(1, max(0.1, quality))
        let formats = exportFormats.filter { ["md", "txt", "srt", "vtt", "json"].contains($0) }
        s.exportFormats = formats.isEmpty ? ["md"] : formats
        if !["clean", "timestamps", "plain", "markdown"].contains(copyFormat) { s.copyFormat = "clean" }
        return s
    }
}
