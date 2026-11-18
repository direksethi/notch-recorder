import Common
import CoreML
import FluidAudio
import Foundation

/// Parakeet TDT 0.6B v2 (English) and Silero VAD on the Neural Engine, the
/// same models FluidVoice uses. Loaded per recording, released after.
public actor FluidSpeechEngine: SpeechEngine {
    private let store: ModelStore
    private var asr: AsrManager?
    private var vad: VadManager?
    private var vadStates: [Common.AudioSource: VadStreamState] = [:]
    private var decoderLayers = 2

    public init(store: ModelStore = ModelStore()) {
        self.store = store
    }

    public func load() async throws {
        if asr != nil { return }
        store.seedFromFluidVoice()
        let started = Date()
        let models = try await AsrModels.load(from: store.asrDirectory, version: .v2)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        decoderLayers = await manager.decoderLayerCount
        vad = try await VadManager(config: VadConfig(defaultThreshold: 0.5), modelDirectory: store.vadBaseDirectory)
        asr = manager
        vadStates = [:]
        Log.transcript.info("speech models loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
    }

    public func unload() async {
        await asr?.cleanup()
        asr = nil
        vad = nil
        vadStates = [:]
    }

    public func vadProbability(_ chunk: [Float], source: Common.AudioSource) async throws -> Float {
        guard let vad else { throw TranscriptError.modelUnavailable("not loaded") }
        let state = vadStates[source] ?? .initial()
        let result = try await vad.processStreamingChunk(chunk, state: state)
        vadStates[source] = result.state
        return result.probability
    }

    public func transcribe(_ samples: [Float], source: Common.AudioSource) async throws -> (text: String, confidence: Double) {
        guard let asr else { throw TranscriptError.modelUnavailable("not loaded") }
        // Parakeet needs at least one second; pad short utterances with silence.
        var audio = samples
        if audio.count < 16_000 { audio += [Float](repeating: 0, count: 16_000 - audio.count) }
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await asr.transcribe(audio, decoderState: &state)
        return (result.text, Double(result.confidence))
    }
}
