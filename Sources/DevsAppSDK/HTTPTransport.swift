import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one seam the SDK needs to reach the network.
///
/// Conform your own type to swap in a different HTTP stack, or to answer from
/// fixtures in tests without touching `URLProtocol`.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The default transport, backed by `URLSession`.
public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// A transport with its own ephemeral session — no shared cookie or cache
    /// state with the rest of the app.
    public static var ephemeral: URLSessionTransport {
        URLSessionTransport(session: URLSession(configuration: .ephemeral))
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// A transport built from a closure — the shortest path to a stubbed test.
///
/// ```swift
/// let transport = ClosureTransport { request in
///     (fixtureData, HTTPURLResponse(url: request.url!, statusCode: 200,
///                                   httpVersion: nil, headerFields: nil)!)
/// }
/// ```
public struct ClosureTransport: HTTPTransport {
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public init(_ handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}
