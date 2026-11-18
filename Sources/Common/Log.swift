import os

/// Unified logging. Read with:
/// `log show --predicate 'subsystem == "com.direksethi.NotchRecorder"' --last 1h`
public enum Log {
    public static let subsystem = "com.direksethi.NotchRecorder"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let recorder = Logger(subsystem: subsystem, category: "recorder")
    public static let transcript = Logger(subsystem: subsystem, category: "transcript")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let bridge = Logger(subsystem: subsystem, category: "bridge")
}
