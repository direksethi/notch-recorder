import Common
import Foundation

/// Dispatches `{ method, params }` messages from the page to typed handlers
/// and returns `{ ok, value }` or `{ ok: false, error }`.
public final class BridgeRouter: @unchecked Sendable {
    public typealias Raw = @Sendable (Data) async throws -> Data

    private var handlers: [String: Raw] = [:]
    private let encoder = JSONEncoder()

    public init() {}

    public func register<P: Decodable, R: Encodable>(
        _ method: String, _ handler: @escaping @Sendable (P) async throws -> R
    ) {
        let encoder = self.encoder
        handlers[method] = { data in
            let params = try JSONDecoder().decode(P.self, from: data)
            let result = try await handler(params)
            return try encoder.encode(result)
        }
    }

    public var methods: [String] { handlers.keys.sorted() }

    /// `params` is the Foundation object WebKit delivered.
    public func handle(method: String, params: Any?) async -> [String: Any] {
        do {
            guard let handler = handlers[method] else {
                throw BridgeFailure(.InvalidParams, "Unknown request \(method).")
            }
            let body = params ?? [String: Any]()
            let data = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
            let result = try await handler(data)
            let value = try JSONSerialization.jsonObject(with: result, options: [.fragmentsAllowed])
            return ["ok": true, "value": value]
        } catch {
            let failure = BridgeFailure.from(error)
            if failure.code != .Cancelled {
                Log.bridge.error("\(method, privacy: .public) failed: \(failure.message, privacy: .public)")
            }
            var payload: [String: Any] = ["code": failure.code.rawValue, "message": failure.message]
            if let detail = failure.detail { payload["detail"] = detail }
            return ["ok": false, "error": payload]
        }
    }
}

/// `{}` params.
public struct NoParams: Codable, Sendable {}
public struct IdParams: Codable, Sendable { public var id: String }
/// Encodes as JSON null.
public struct Nothing: Encodable, Sendable {
    public init() {}
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encodeNil()
    }
}
