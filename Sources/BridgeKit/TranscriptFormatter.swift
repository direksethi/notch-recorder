import Common
import Foundation
import JavaScriptCore

/// Formats transcript files with the same TypeScript code the Library uses
/// (web/packages/core, bundled as core.jsc.js). A JavaScriptCore context is
/// created per call and released straight after, so it costs nothing idle.
public struct TranscriptFormatter: Sendable {
    public let script: URL

    public init(script: URL) {
        self.script = script
    }

    public func format(_ detail: RecordingDetailDTO, as format: String) throws -> String {
        let source = try String(contentsOf: script, encoding: .utf8)
        guard let context = JSContext() else { throw BridgeFailure(.Failed, "JavaScript is unavailable.") }
        var thrown: String?
        context.exceptionHandler = { _, value in thrown = value?.toString() }
        context.evaluateScript(source)
        let json = String(data: try JSONEncoder().encode(detail), encoding: .utf8)!
        let fn = context.objectForKeyedSubscript("NotchCore")?.objectForKeyedSubscript("formatExport")
        let result = fn?.call(withArguments: [json, format])
        if let thrown { throw BridgeFailure(.Failed, "Couldn't format the transcript.", detail: thrown) }
        guard let text = result?.toString(), result?.isString == true else {
            throw BridgeFailure(.Failed, "Couldn't format the transcript.")
        }
        return text
    }
}
