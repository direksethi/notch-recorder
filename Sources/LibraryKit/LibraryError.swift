import Foundation

public enum LibraryError: Error, Equatable, LocalizedError {
    case notFound(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "Recording \(id) was not found."
        case .database(let message): "The library database failed: \(message)"
        }
    }
}
