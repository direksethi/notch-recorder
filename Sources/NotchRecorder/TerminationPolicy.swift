/// What to do when the app is asked to quit.
enum TerminationPolicy: Equatable {
    /// Nothing running: quit straight away.
    case now
    /// A recording is running and the user chose Quit: confirm first.
    case ask
    /// Logout, restart or shutdown: no time to ask; stop cleanly and quit.
    case stopThenQuit

    static func decide(isRecording: Bool, hasJob: Bool, systemIsShuttingDown: Bool) -> TerminationPolicy {
        if isRecording { return systemIsShuttingDown ? .stopThenQuit : .ask }
        return hasJob ? .stopThenQuit : .now
    }
}
