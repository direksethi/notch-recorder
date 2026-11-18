import BridgeKit
import Common
import Foundation
import LibraryKit
import RecorderKit
import ServiceManagement

/// Loads and saves AppSettings in the library database.
@MainActor
final class SettingsStore {
    private let repo: LibraryRepository
    private(set) var current: AppSettings
    var onChange: ((AppSettings) -> Void)?

    init(repo: LibraryRepository) {
        self.repo = repo
        if let json = try? repo.setting("settings"), let data = json.data(using: .utf8),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            current = s.validated
        } else {
            current = AppSettings()
        }
    }

    func update(_ patch: [String: Any]) throws -> AppSettings {
        let next = try current.merging(patch).validated
        let data = try JSONEncoder().encode(next)
        try repo.setSetting("settings", String(data: data, encoding: .utf8)!)
        let loginChanged = next.launchAtLogin != current.launchAtLogin
        current = next
        if loginChanged { applyLaunchAtLogin() }
        onChange?(next)
        return next
    }

    func applyLaunchAtLogin() {
        do {
            if current.launchAtLogin {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordingSettings(captureMic: Bool) -> RecordingSettings {
        var r = RecordingSettings()
        r.displayID = current.displayId
        r.micDeviceID = current.micDeviceId
        r.captureMicrophone = captureMic
        r.showCursor = current.showCursor
        r.scale = current.scale
        r.retinaPointScale = current.retinaPointScale
        r.fps = Int32(current.fps)
        r.quality = current.quality
        return r
    }
}
