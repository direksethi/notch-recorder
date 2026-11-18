import AppKit
import AVFoundation
import CoreGraphics

enum Permissions {
    static var screen: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards macOS only lets
    /// the user change it in System Settings.
    @discardableResult
    static func requestScreen() -> Bool { CGRequestScreenCaptureAccess() }

    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestMicrophone() async -> Bool {
        switch microphone {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static func openSettings(_ kind: String) {
        let pane = kind == "microphone" ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
