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
///     case .unauthorized: message = "Sign in again."
///     case .network:      message = "Check your connection."
///     case .notFound:     message = "That app is no longer listed."
///     case .api:          message = "devsapp.app is having trouble."
///     case .decoding:     message = "Unexpected response."
///     }
/// }
/// ```
public enum DevsAppError: Error, Sendable {
    /// No HTTP response arrived: offline, DNS or TLS failure, or a timeout.
    case network(underlying: any Error)

    /// HTTP 404 — no app has that slug.
    case notFound(slug: String)

    /// HTTP 401 or 403 — no token was sent, or the server rejected the one it
    /// got. Retrying with the same token will not help; get a new one and
    /// either build a client with it or call `DevsAppClient.setToken(_:)`.
    case unauthorized(statusCode: Int, message: String)

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
        case .unauthorized(let status, _):
            return status == 401
                ? "This app’s access token is missing or has expired."
                : "This app’s access token isn’t allowed to read that."
        case .api(_, let message):
            return message
        case .decoding:
            return "Unexpected response from devsapp.app."
        }
    }

    /// Whether re-authenticating is what this failure calls for.
    public var requiresAuthentication: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// The HTTP status behind the failure, when there was one.
    public var statusCode: Int? {
        switch self {
        case .notFound: return 404
        case .api(let code, _): return code
        case .unauthorized(let code, _): return code
        case .network, .decoding: return nil
        }
    }
}
