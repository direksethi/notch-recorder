import Common
import FluidAudio
import Foundation

/// The app keeps its own copy of the speech models so a FluidVoice update can
/// never break it (or the other way round). On first use the copy is made
/// from FluidVoice's download with an APFS clone, which takes no extra disk
/// space and no network.
public struct ModelStore: Sendable {
    public let paths: AppPaths
    /// The folder FluidAudio itself loads Parakeet v2 from.
    public static var asrFolder: String { AsrModels.defaultCacheDirectory(for: .v2).lastPathComponent }
    /// Folder names FluidVoice's (possibly older) FluidAudio may have used.
    static let fluidVoiceFolders = ["parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v2-coreml"]

    public init(paths: AppPaths = .live) {
        self.paths = paths
    }

    /// `<App Support>/NotchRecorder/Models/parakeet-tdt-0.6b-v2-coreml`
    public var asrDirectory: URL { paths.models.appendingPathComponent(Self.asrFolder, isDirectory: true) }

    /// FluidAudio's VAD loader appends "Models/silero-vad-coreml" to this.
    public var vadBaseDirectory: URL { paths.root }

    public static var fluidVoiceModels: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    /// Clones FluidVoice's Parakeet v2 when ours is missing. Missing files
    /// after that are downloaded by FluidAudio on load.
    public func seedFromFluidVoice(source: URL = ModelStore.fluidVoiceModels) {
        let fm = FileManager.default
        try? fm.createDirectory(at: paths.models, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: asrDirectory.path),
              let from = Self.fluidVoiceFolders.map({ source.appendingPathComponent($0) })
                .first(where: { fm.fileExists(atPath: $0.appendingPathComponent("Encoder.mlmodelc").path) })
        else { return }
        do {
            try fm.copyItem(at: from, to: asrDirectory)
            Log.transcript.info("seeded speech model from FluidVoice")
        } catch {
            Log.transcript.error("could not seed model: \(error.localizedDescription, privacy: .public)")
        }
    }
}
