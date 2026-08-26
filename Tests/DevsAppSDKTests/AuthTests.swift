import Foundation
import Testing
@testable import DevsAppSDK

/// The API requires `Authorization: Bearer <token>`; these cover how the client
/// carries it and what happens when the server rejects it.
@Suite("authentication")
struct AuthTests {
    /// Captures the Authorization header of every request.
    actor HeaderLog {
        private(set) var values: [String?] = []
        func record(_ value: String?) { values.append(value) }
        var count: Int { values.count }
        var last: String?? { values.last }
    }

    private func client(
        token: String? = nil,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        maxRetries: Int = 2,
        cacheTTL: TimeInterval = 300,
        log: HeaderLog? = nil,
        respond: @escaping @Sendable (URLRequest, Int) async -> (Data, Int) = { _, _ in
            (Data(Fixtures.list.utf8), 200)
        }
    ) -> DevsAppClient {
        let counter = Counter()
        return DevsAppClient(configuration: DevsAppConfiguration(
            cacheTTL: cacheTTL,
            maxRetries: maxRetries,
            retryBackoff: 0,
            transport: ClosureTransport { request in
                await log?.record(request.value(forHTTPHeaderField: "Authorization"))
                let attempt = await counter.increment()
                let (data, status) = await respond(request, attempt)
                return (data, response(request.url!, status))
            },
            token: token,
            tokenProvider: tokenProvider
        ))
    }

    actor Counter {
        private(set) var value = 0
        func increment() -> Int { value += 1; return value }
    }

    @Test("sends no Authorization header when no token is configured")
    func noToken() async throws {
        let log = HeaderLog()
        let client = client(log: log)

        _ = try await client.listApps()

        #expect(await log.values == [nil])
        #expect(await client.isAuthenticated == false)
    }

    @Test("sends a bearer token when given one")
    func withToken() async throws {
        let log = HeaderLog()
        let client = client(token: "abc123", log: log)

        _ = try await client.listApps()

        #expect(await log.values == ["Bearer abc123"])
        #expect(await client.isAuthenticated)
    }

    @Test("does not double-prefix a token that already says Bearer")
    func noDoublePrefix() async throws {
        let log = HeaderLog()
        let client = client(token: "Bearer abc123", log: log)

        _ = try await client.listApps()

        #expect(await log.values == ["Bearer abc123"])
    }

    @Test("treats a blank token as no token")
    func blankToken() async throws {
        let log = HeaderLog()
        let client = client(token: "   ", log: log)

        _ = try await client.listApps()

        #expect(await log.values == [nil])
    }

    @Test("asks a tokenProvider once per call, not once per retry")
    func providerCalledOncePerCall() async throws {
        let calls = Counter()
        let client = client(
            tokenProvider: { "fresh-\(await calls.increment())" },
            respond: { _, attempt in
                attempt < 3
                    ? (Data(#"{"ok":false}"#.utf8), 503)
                    : (Data(Fixtures.list.utf8), 200)
            }
        )

        _ = try await client.listApps()

        #expect(await calls.value == 1)
    }

    @Test("picks up a new token from the provider on the next call")
    func providerRefresh() async throws {
        actor Box { var value = "first"; func set(_ v: String) { value = v } }
        let box = Box()
        let log = HeaderLog()
        let client = client(tokenProvider: { await box.value }, cacheTTL: 0, log: log)

        _ = try await client.listApps()
        await box.set("second")
        _ = try await client.listApps()

        #expect(await log.values == ["Bearer first", "Bearer second"])
    }

    @Test("maps 401 to .unauthorized with the server's message")
    func unauthorized() async throws {
        let client = client(token: "stale", respond: { _, _ in
            (Data(#"{"ok":false,"error":"Missing or invalid Authorization: Bearer token."}"#.utf8), 401)
        })

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .unauthorized(let status, let message) = error else {
                Issue.record("expected .unauthorized, got \(error)")
                return
            }
            #expect(status == 401)
            #expect(message.contains("Authorization"))
            #expect(error.requiresAuthentication)
            #expect(error.statusCode == 401)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("maps 403 to .unauthorized")
    func forbidden() async throws {
        let client = client(token: "wrong-scope", respond: { _, _ in
            (Data(#"{"ok":false,"error":"Forbidden."}"#.utf8), 403)
        })

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .unauthorized(let status, _) = error else {
                Issue.record("expected .unauthorized, got \(error)")
                return
            }
            #expect(status == 403)
        }
    }

    @Test("never retries a 401")
    func noRetry() async throws {
        let attempts = Counter()
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: 3,
            retryBackoff: 0,
            transport: ClosureTransport { request in
                _ = await attempts.increment()
                return (Data(#"{"ok":false,"error":"nope"}"#.utf8), response(request.url!, 401))
            },
            token: "stale"
        ))

        await #expect(throws: DevsAppError.self) { try await client.listApps() }
        #expect(await attempts.value == 1)
    }

    @Test("a 401 on a slug lookup is unauthorized, not not-found")
    func detail401NotMistakenForMissing() async throws {
        let client = client(respond: { _, _ in
            (Data(#"{"ok":false,"error":"nope"}"#.utf8), 401)
        })

        do {
            _ = try await client.app(slug: "quickclean")
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .unauthorized = error else {
                Issue.record("expected .unauthorized, got \(error)")
                return
            }
        }
    }

    @Test("setToken drops responses fetched with the previous token")
    func setTokenClearsCache() async throws {
        let log = RequestLog()
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            retryBackoff: 0,
            transport: fakeAPI(log: log),
            token: "first"
        ))

        _ = try await client.listApps()
        _ = try await client.listApps()
        #expect(await log.count == 1)

        await client.setToken("second")
        _ = try await client.listApps()

        #expect(await log.count == 2)
    }

    @Test("setToken to the same value keeps the cache")
    func setSameToken() async throws {
        let log = RequestLog()
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            transport: fakeAPI(log: log),
            token: "same"
        ))

        _ = try await client.listApps()
        await client.setToken("same")
        _ = try await client.listApps()

        #expect(await log.count == 1)
    }

    @Test("setToken is ignored when a tokenProvider owns the token")
    func setTokenWithProvider() async throws {
        let log = HeaderLog()
        let client = client(tokenProvider: { "from-provider" }, cacheTTL: 0, log: log)

        await client.setToken("ignored")
        _ = try await client.listApps()

        #expect(await log.values == ["Bearer from-provider"])
    }
}
