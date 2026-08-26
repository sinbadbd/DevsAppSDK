import Foundation

/// Tuning for ``DevsAppClient``. Every value has a default aimed at a mobile
/// app on an unreliable connection.
public struct DevsAppConfiguration: Sendable {
    /// The live endpoint.
    public static let defaultBaseURL = URL(string: "https://devsapp.app/api/apps.php")!

    /// Endpoint to call. Override to point at a staging server.
    public var baseURL: URL

    /// Per-attempt timeout. With retries, total wall time can exceed this.
    public var timeout: TimeInterval

    /// How long a response stays fresh in memory. The server sends
    /// `cache-control: public, max-age=300`, which is where 300s comes from.
    /// Set to `0` to disable caching.
    public var cacheTTL: TimeInterval

    /// Extra attempts after a failure. `0` disables retrying.
    public var maxRetries: Int

    /// Base delay between retries; doubles each attempt.
    public var retryBackoff: TimeInterval

    /// Merged into every request.
    public var additionalHeaders: [String: String]

    /// How requests actually reach the network. Swap for tests.
    public var transport: any HTTPTransport

    public init(
        baseURL: URL = DevsAppConfiguration.defaultBaseURL,
        timeout: TimeInterval = 15,
        cacheTTL: TimeInterval = 300,
        maxRetries: Int = 2,
        retryBackoff: TimeInterval = 0.3,
        additionalHeaders: [String: String] = [:],
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.cacheTTL = cacheTTL
        self.maxRetries = max(0, maxRetries)
        self.retryBackoff = retryBackoff
        self.additionalHeaders = additionalHeaders
        self.transport = transport
    }
}
