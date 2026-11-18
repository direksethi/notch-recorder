import Foundation
import TranscriptKit

// Usage: ASRCheck <audio file>
// Transcribes a file with the real models and prints timing and memory.
let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: ASRCheck <audio file>")
    exit(2)
}
func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return Double(info.resident_size) / 1_048_576
}
let url = URL(fileURLWithPath: args[1])
let engine = FluidSpeechEngine()
let started = Date()
do {
    try await engine.load()
    print(String(format: "loaded in %.2f s, rss %.0f MB", Date().timeIntervalSince(started), residentMB()))
    let duration = try await AudioReader.duration(of: url)
    let t0 = Date()
    let drafts = try await Retranscriber(engine: engine).run(
        .init(micAudio: url, systemAudio: nil, video: nil, fromMs: 0, durationMs: Int64(duration * 1000))) { _ in }
    let took = Date().timeIntervalSince(t0)
    for d in drafts { print("[\(d.startMs) - \(d.endMs)] \(d.text)") }
    print(String(format: "%.1f s of audio in %.2f s (%.0fx), rss %.0f MB", duration, took, duration / took, residentMB()))
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
