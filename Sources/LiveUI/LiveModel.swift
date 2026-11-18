import Common
import Foundation
import Observation

public enum LivePhase: Equatable, Sendable {
    case hidden
    /// Loading the speech model; capture has not started yet.
    case preparing
    case recording
    case paused
    case finishing
    /// Something the user needs to read: the window stays open until closed.
    case notice(title: String, message: String)
}

public struct LiveLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var source: AudioSource
    public var text: String

    public init(source: AudioSource, text: String) {
        id = UUID()
        self.source = source
        self.text = text
    }
}

/// Everything the live transcript window shows. Updated on the main actor.
@MainActor
@Observable
public final class LiveModel {
    public var phase: LivePhase = .hidden
    public var elapsed: TimeInterval = 0
    public var meLevel: Float = 0
    public var othersLevel: Float = 0
    public var lines: [LiveLine] = []
    public var partials: [AudioSource: String] = [:]
    /// Why live transcription is off or stopped, if it is.
    public var transcriptNote: String?
    public var warning: String?
    public var showPartials = true

    // Actions, wired by the app.
    public var onStop: () -> Void = {}
    public var onCancel: () -> Void = {}
    public var onOpenLibrary: () -> Void = {}
    public var onClose: () -> Void = {}

    public init() {}

    /// The window keeps the whole recording; this only guards memory on
    /// very long sessions.
    public static let maxLines = 2_000

    public func addFinal(_ source: AudioSource, _ text: String) {
        lines.append(LiveLine(source: source, text: text))
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        partials[source] = nil
    }

    public func setPartial(_ source: AudioSource, _ text: String) {
        partials[source] = text.isEmpty ? nil : text
    }

    public func reset() {
        lines = []
        partials = [:]
        elapsed = 0
        meLevel = 0
        othersLevel = 0
        transcriptNote = nil
        warning = nil
    }

    public var isActive: Bool {
        switch phase {
        case .preparing, .recording, .paused, .finishing: true
        case .hidden, .notice: false
        }
    }

    public static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
