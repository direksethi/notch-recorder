import Common
import Foundation

/// `state.json` tells the build script (and anything else) whether a
/// recording is running, so an update never replaces the app mid-recording.
struct StateFile {
    let url: URL

    func write(state: String, recordingId: String?) {
        var body: [String: Any] = ["state": state, "pid": ProcessInfo.processInfo.processIdentifier, "updatedAt": Date().timeIntervalSince1970]
        if let recordingId { body["recordingId"] = recordingId }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
