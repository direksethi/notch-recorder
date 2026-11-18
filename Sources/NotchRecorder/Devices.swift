import AppKit
import AVFoundation
import BridgeKit

enum Devices {
    static func list() -> DevicesDTO {
        let main = CGMainDisplayID()
        let displays = NSScreen.screens.compactMap { screen -> DisplayDTO? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayDTO(
                id: id, name: screen.localizedName,
                width: mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor),
                height: mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor),
                isMain: id == main)
        }
        let defaultMic = AVCaptureDevice.default(for: .audio)?.uniqueID
        let mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices
            .map { MicrophoneDTO(id: $0.uniqueID, name: $0.localizedName, isDefault: $0.uniqueID == defaultMic) }
        return DevicesDTO(displays: displays, microphones: mics)
    }
}
