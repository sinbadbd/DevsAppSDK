import Foundation
import Testing
@testable import DevsAppSDK

@Suite("listApps")
struct ListTests {
    @Test("parses the list response")
    func parses() async throws {
        let log = RequestLog()
        let apps = try await makeClient(log: log).listApps()

        #expect(apps.count == 2)
        #expect(await log.last?.query == nil)

        let first = try #require(apps.first)
        #expect(first.slug == "quickclean")
        #expect(first.fullName == "QuickClean: One-tap clean")
        #expect(first.screenshots.count == 2)
        #expect(first.screenshots[0].url.hasSuffix("quickclean-0.png"))
        #expect(first.platforms == ["iPhone", "iPad"])
        #expect(first.links.appStore?.contains("apps.apple.com") == true)
        #expect(first.links.playStore == nil)
        #expect(first.languages == 14)
        #expect(first.hasIAP)
        #expect(!first.macSupported)
        #expect(first.year == 2025)
        #expect(first.supportsIOS)
        #expect(!first.supportsAndroid)
    }

    @Test("caches the list and reuses it")
    func caches() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        _ = try await client.listApps()
        _ = try await client.listApps()

        #expect(await log.count == 1)
    }

    @Test("forceRefresh bypasses the cache")
    func forceRefresh() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        _ = try await client.listApps()
        _ = try await client.listApps(forceRefresh: true)

        #expect(await log.count == 2)
    }

    @Test("a zero TTL refetches every time")
    func noCache() async throws {
        let log = RequestLog()
        let client = makeClient(log: log, cacheTTL: 0)

        _ = try await client.listApps()
        _ = try await client.listApps()

        #expect(await log.count == 2)
    }

    @Test("filters by category, platform, tag and query on device")
    func filters() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        #expect(try await client.listApps(category: "Developer Tools").map(\.slug) == ["sendman"])
        #expect(try await client.listApps(platform: "android").map(\.slug) == ["sendman"])
        #expect(try await client.listApps(tag: "ai cleaner").map(\.slug) == ["quickclean"])
        #expect(try await client.listApps(query: "storage").map(\.slug) == ["quickclean"])
        #expect(try await client.listApps(query: "nothing matches").isEmpty)
        #expect(try await client.listApps(category: "  ").count == 2)

        // All of that came from one download.
        #expect(await log.count == 1)
    }

    @Test("concurrent calls share one request")
    func coalesces() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        async let a = client.listApps()
        async let b = client.listApps()
        async let c = client.listApps()
        _ = try await (a, b, c)

        #expect(await log.count == 1)
    }

    @Test("collects categories and platforms")
    func facets() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        #expect(try await client.categories() == ["Developer Tools", "Utilities"])
        #expect(try await client.platforms() == ["Android", "iPad", "iPhone"])
    }
}

@Suite("app(slug:)")
struct DetailTests {
    @Test("fetches detail by slug")
    func fetches() async throws {
        let log = RequestLog()
        let app = try await makeClient(log: log).app(slug: "quickclean")

        let query = try #require(await log.last).query
        #expect(query == "slug=quickclean")
        #expect(app.version == "1.0.1")
        #expect(app.categories == ["Utilities", "Privacy"])
    }

    @Test("serves detail from a warm list cache without a request")
    func servesFromListCache() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        _ = try await client.listApps()
        let app = try await client.app(slug: "quickclean")

        #expect(await log.count == 1)
        #expect(app.slug == "quickclean")
        #expect(app.version == "1.0.0") // the list's copy
    }

    @Test("forceRefresh hits the detail endpoint even with a warm cache")
    func forceRefresh() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        _ = try await client.listApps()
        let app = try await client.app(slug: "quickclean", forceRefresh: true)

        #expect(await log.count == 2)
        #expect(app.version == "1.0.1") // the detail endpoint's copy
    }

    @Test("caches detail responses")
    func caches() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        _ = try await client.app(slug: "quickclean")
        _ = try await client.app(slug: "quickclean")

        #expect(await log.count == 1)
    }

    @Test("throws notFound for an unknown slug")
    func unknownSlug() async throws {
        let client = makeClient(log: RequestLog())

        await #expect(throws: DevsAppError.self) {
            try await client.app(slug: "does-not-exist")
        }

        do {
            _ = try await client.app(slug: "does-not-exist")
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .notFound(let slug) = error else {
                Issue.record("expected .notFound, got \(error)")
                return
            }
            #expect(slug == "does-not-exist")
            #expect(error.statusCode == 404)
        }
    }

    @Test("rejects an empty slug without a request")
    func emptySlug() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        await #expect(throws: DevsAppError.self) {
            try await client.app(slug: "   ")
        }
        #expect(await log.count == 0)
    }

    @Test("appIfExists returns nil instead of throwing")
    func ifExists() async throws {
        let client = makeClient(log: RequestLog())

        #expect(try await client.appIfExists(slug: "does-not-exist") == nil)
        #expect(try await client.appIfExists(slug: "quickclean")?.slug == "quickclean")
    }
}

@Suite("failures")
struct FailureTests {
    /// Counts attempts across retries.
    actor Counter {
        private(set) var value = 0
        func increment() -> Int {
            value += 1
            return value
        }
    }

    private func client(
        maxRetries: Int = 2,
        _ handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) -> DevsAppClient {
        DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: maxRetries,
            retryBackoff: 0,
            transport: ClosureTransport(handler)
        ))
    }

    @Test("retries a 5xx, then succeeds")
    func retriesThenSucceeds() async throws {
        let counter = Counter()
        let client = client { request in
            let attempt = await counter.increment()
            if attempt < 3 {
                return (Data(#"{"ok":false}"#.utf8), response(request.url!, 503))
            }
            return (Data(Fixtures.list.utf8), response(request.url!, 200))
        }

        #expect(try await client.listApps().count == 2)
        #expect(await counter.value == 3)
    }

    @Test("gives up after maxRetries and reports the server's message")
    func givesUp() async throws {
        let counter = Counter()
        let client = client(maxRetries: 1) { request in
            _ = await counter.increment()
            return (
                Data(#"{"ok":false,"error":"Down for maintenance."}"#.utf8),
                response(request.url!, 500)
            )
        }

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .api(let status, let message) = error else {
                Issue.record("expected .api, got \(error)")
                return
            }
            #expect(status == 500)
            #expect(message == "Down for maintenance.")
        }
        #expect(await counter.value == 2)
    }

    @Test("never retries a 404")
    func noRetryOn404() async throws {
        let counter = Counter()
        let client = client { request in
            _ = await counter.increment()
            return (Data(Fixtures.notFound.utf8), response(request.url!, 404))
        }

        await #expect(throws: DevsAppError.self) {
            try await client.app(slug: "gone")
        }
        #expect(await counter.value == 1)
    }

    @Test("maps a connection failure to .network")
    func connectionFailure() async throws {
        let client = client(maxRetries: 0) { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .network(let underlying) = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
            #expect((underlying as? URLError)?.code == .notConnectedToInternet)
            #expect(error.errorDescription?.contains("connection") == true)
        }
    }

    @Test("maps a timeout to .network")
    func timeout() async throws {
        let client = client(maxRetries: 0) { _ in throw URLError(.timedOut) }

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .network(let underlying) = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
            #expect((underlying as? URLError)?.code == .timedOut)
        }
    }

    @Test("maps a non-JSON body to .decoding")
    func malformedJSON() async throws {
        let client = client { request in
            (Data("<html>gateway error</html>".utf8), response(request.url!, 200))
        }

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test("maps a missing apps array to .decoding")
    func missingArray() async throws {
        let client = client { request in
            (Data(#"{"ok":true}"#.utf8), response(request.url!, 200))
        }

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test("treats ok:false on a 200 as a failure")
    func okFalseOn200() async throws {
        let client = client { request in
            (Data(#"{"ok":false,"error":"Temporarily unavailable."}"#.utf8), response(request.url!, 200))
        }

        do {
            _ = try await client.listApps()
            Issue.record("expected a throw")
        } catch let error as DevsAppError {
            guard case .api(_, let message) = error else {
                Issue.record("expected .api, got \(error)")
                return
            }
            #expect(message == "Temporarily unavailable.")
        }
    }

    @Test("clearCache sends the next call back to the network")
    func clearCache() async throws {
        let log = RequestLog()
        let client = makeClient(log: log)

        _ = try await client.listApps()
        await client.clearCache()
        _ = try await client.listApps()

        #expect(await log.count == 2)
    }

    @Test("decodes UTF-8 bodies correctly")
    func utf8() async throws {
        let body = Fixtures.detail.replacingOccurrences(
            of: "QuickClean: One-tap clean",
            with: "QuickClean — Nettoyage éclair"
        )
        let client = client { request in
            (Data(body.utf8), response(request.url!, 200))
        }

        let app = try await client.app(slug: "quickclean")
        #expect(app.fullName == "QuickClean — Nettoyage éclair")
    }

    @Test("sends configured headers")
    func headers() async throws {
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            additionalHeaders: ["X-Client": "tests/1.0"],
            transport: ClosureTransport { request in
                #expect(request.value(forHTTPHeaderField: "X-Client") == "tests/1.0")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
                return (Data(Fixtures.list.utf8), response(request.url!, 200))
            }
        ))

        _ = try await client.listApps()
    }

    @Test("honours a custom base URL")
    func baseURL() async throws {
        let staging = URL(string: "https://staging.example.com/api/apps.php")!
        let log = RequestLog()
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            baseURL: staging,
            transport: ClosureTransport { request in
                await log.record(request.url!)
                return (Data(Fixtures.list.utf8), response(request.url!, 200))
            }
        ))

        _ = try await client.listApps()
        #expect(await log.last?.host == "staging.example.com")
    }
}
