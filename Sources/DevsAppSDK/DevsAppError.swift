import Foundation

/// Every failure this SDK reports.
///
/// `switch` over it is exhaustive, so adding a case surfaces at compile time in
/// code that handles the error:
///
/// ```swift
/// do {
///     _ = try await client.listApps()
/// } catch let error as DevsAppError {
///     switch error {
///     case .network:   message = "Check your connection."
///     case .notFound:  message = "That app is no longer listed."
///     case .api:       message = "devsapp.app is having trouble."
///     case .decoding:  message = "Unexpected response."
///     }
/// }
/// ```
public enum DevsAppError: Error, Sendable {
    /// No HTTP response arrived: offline, DNS or TLS failure, or a timeout.
    case network(underlying: any Error)

    /// HTTP 404 — no app has that slug.
    case notFound(slug: String)

    /// The server answered unsuccessfully: 5xx, a rate limit, or `{"ok": false}`.
    case api(statusCode: Int?, message: String)

    /// The response was not the JSON shape this SDK expects.
    case decoding(underlying: any Error)
}

extension DevsAppError: LocalizedError {
    /// A message worth putting in front of a person.
    public var errorDescription: String? {
        switch self {
        case .network:
            return "Can’t reach devsapp.app. Check your connection."
        case .notFound(let slug):
            return "No app found for “\(slug)”."
        case .api(_, let message):
            return message
        case .decoding:
            return "Unexpected response from devsapp.app."
        }
    }

    /// The HTTP status behind the failure, when there was one.
    public var statusCode: Int? {
        switch self {
        case .notFound: return 404
        case .api(let code, _): return code
        case .network, .decoding: return nil
        }
    }
}
