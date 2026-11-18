/// Who is speaking in a transcript segment. The microphone is always the user
/// ("me"), system audio is everyone else ("others"). "speaker" is used when a
/// recording is transcribed from the mixed track and the source is unknown.
public enum AudioSource: String, Codable, Sendable, CaseIterable {
    case me
    case others
    case speaker
}
