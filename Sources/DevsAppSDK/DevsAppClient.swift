import Foundation

/// Client for the devsapp.app apps API.
///
/// Covers the two endpoints the API exposes:
///
/// - ``listApps(category:platform:tag:query:forceRefresh:)`` — `GET /api/apps.php`
/// - ``app(slug:forceRefresh:)`` — `GET /api/apps.php?slug=<slug>`
///
/// ```swift
/// let client = DevsAppClient()
/// let apps = try await client.listApps()
/// let app = try await client.app(slug: "quickclean")
/// ```
///
/// It is an `actor`, so the cache it keeps is safe to share across tasks —
/// make one and hold onto it rather than creating one per screen.
public actor DevsAppClient {
    private let configuration: DevsAppConfiguration
    private var listCache: TTLCache<String, [DevsApp]>
    private var detailCache: TTLCache<String, DevsApp>
    private var inFlight: [String: Task<Data, any Error>] = [:]
    private var token: String?

    private static let listCacheKey = "__all__"

    public init(configuration: DevsAppConfiguration = DevsAppConfiguration()) {
        self.configuration = configuration
        self.token = configuration.token
        self.listCache = TTLCache(ttl: configuration.cacheTTL)
        self.detailCache = TTLCache(ttl: configuration.cacheTTL)
    }

    /// Whether this client will send an `Authorization` header. A client built
    /// with a `tokenProvider` reports `true` without calling it.
    public var isAuthenticated: Bool {
        token != nil || configuration.tokenProvider != nil
    }

    /// Replaces the bearer token at runtime — after a sign-in, or once a
    /// refresh produces a new one. Pass `nil` to sign out.
    ///
    /// Cached responses were fetched as whoever held the previous token, so
    /// changing it drops them. Has no effect when a `tokenProvider` is set:
    /// there the provider is the source of truth.
    public func setToken(_ newToken: String?) {
        guard configuration.tokenProvider == nil else { return }
        guard token != newToken else { return }
        token = newToken
        clearCache()
    }

    /// The `Authorization` value for the next request, or nil to send none.
    private func bearerToken() async -> String? {
        let resolved: String?
        if let provider = configuration.tokenProvider {
            resolved = await provider()
        } else {
            resolved = token
        }
        guard let value = resolved?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        // Accept a raw token or an already-formed header value.
        return value.lowercased().hasPrefix("bearer ") ? value : "Bearer \(value)"
    }

    // MARK: - List

    /// Fetches the app list.
    ///
    /// The API returns every app in one unfiltered response, so `category`,
    /// `platform`, `tag` and `query` are applied **on device** to the fetched
    /// list. They don't reduce what is downloaded — they save you writing the
    /// same `filter` closures, and let a search field run without new requests.
    ///
    /// - Parameters:
    ///   - category: Matches the whole category or one part of a combined one,
    ///     so `"Utilities"` also matches `"Utilities · Privacy"`.
    ///   - platform: Matches an entry of ``DevsApp/platforms``, case-insensitively.
    ///   - tag: Matches an entry of ``DevsApp/tags``, case-insensitively.
    ///   - query: Free text over name, tagline, description, category and tags.
    ///   - forceRefresh: Skip the cache and go to the network.
    /// - Throws: ``DevsAppError``
    public func listApps(
        category: String? = nil,
        platform: String? = nil,
        tag: String? = nil,
        query: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> [DevsApp] {
        var result = try await fetchAll(forceRefresh: forceRefresh)

        if let category = trimmed(category) {
            let wanted = category.lowercased()
            result = result.filter { app in
                app.category.lowercased() == wanted
                    || app.categories.contains { $0.lowercased() == wanted }
            }
        }
        if let platform = trimmed(platform) {
            result = result.filter { $0.hasPlatform(platform) }
        }
        if let tag = trimmed(tag) {
            result = result.filter { $0.hasTag(tag) }
        }
        if let query = trimmed(query) {
            result = result.filter { $0.matches(query) }
        }
        return result
    }

    // MARK: - Detail

    /// Fetches one app by slug.
    ///
    /// Answers from cache when a previous ``listApps(category:platform:tag:query:forceRefresh:)``
    /// or ``app(slug:forceRefresh:)`` call already loaded it, so pushing a
    /// detail screen from a list costs no request.
    ///
    /// - Throws: ``DevsAppError/notFound(slug:)`` when no app has that slug.
    public func app(slug: String, forceRefresh: Bool = false) async throws -> DevsApp {
        let key = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DevsAppError.notFound(slug: slug) }

        if !forceRefresh {
            if let cached = detailCache.value(for: key) ?? cachedFromList(slug: key) {
                return cached
            }
        }

        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "slug", value: key))
        components?.queryItems = items

        guard let url = components?.url else {
            throw DevsAppError.api(statusCode: nil, message: "Could not build a URL for “\(key)”.")
        }

        let data = try await fetchData(url: url, notFoundSlug: key)

        let envelope: DetailEnvelope
        do {
            envelope = try JSONDecoder().decode(DetailEnvelope.self, from: data)
        } catch {
            throw DevsAppError.decoding(underlying: error)
        }
        guard let app = envelope.app else {
            throw DevsAppError.decoding(
                underlying: EnvelopeError.missingKey("app")
            )
        }

        detailCache.insert(app, for: key)
        return app
    }

    /// Like ``app(slug:forceRefresh:)``, but an unknown slug returns `nil`
    /// instead of throwing. Other failures still throw.
    public func appIfExists(slug: String, forceRefresh: Bool = false) async throws -> DevsApp? {
        do {
            return try await app(slug: slug, forceRefresh: forceRefresh)
        } catch DevsAppError.notFound {
            return nil
        }
    }

    // MARK: - Facets

    /// Every distinct category in the catalogue, sorted, with combined
    /// categories split into their parts. For a filter row.
    public func categories(forceRefresh: Bool = false) async throws -> [String] {
        let apps = try await fetchAll(forceRefresh: forceRefresh)
        return Set(apps.flatMap(\.categories)).sorted()
    }

    /// Every distinct platform in the catalogue, sorted.
    public func platforms(forceRefresh: Bool = false) async throws -> [String] {
        let apps = try await fetchAll(forceRefresh: forceRefresh)
        return Set(apps.flatMap(\.platforms)).sorted()
    }

    // MARK: - Cache

    /// Drops every cached response. The next call goes to the network.
    public func clearCache() {
        listCache.removeAll()
        detailCache.removeAll()
    }

    // MARK: - Internals

    private func fetchAll(forceRefresh: Bool) async throws -> [DevsApp] {
        if !forceRefresh, let cached = listCache.value(for: Self.listCacheKey) {
            return cached
        }

        let data = try await fetchData(url: configuration.baseURL, notFoundSlug: nil)

        let envelope: ListEnvelope
        do {
            envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        } catch {
            throw DevsAppError.decoding(underlying: error)
        }
        guard let apps = envelope.apps else {
            throw DevsAppError.decoding(underlying: EnvelopeError.missingKey("apps"))
        }

        listCache.insert(apps, for: Self.listCacheKey)
        // A list response is a detail response for every app in it.
        for app in apps where !app.slug.isEmpty {
            detailCache.insert(app, for: app.slug)
        }
        return apps
    }

    private func cachedFromList(slug: String) -> DevsApp? {
        listCache.value(for: Self.listCacheKey)?.first { $0.slug == slug }
    }

    /// Collapses identical concurrent requests into one, so a list and a detail
    /// view appearing in the same frame don't both hit the network.
    private func fetchData(url: URL, notFoundSlug: String?) async throws -> Data {
        let key = url.absoluteString

        if let existing = inFlight[key] {
            return try await existing.value
        }

        let configuration = self.configuration
        // Resolved once per call, so a provider isn't asked again on each retry.
        let authorization = await bearerToken()
        let task = Task<Data, any Error> {
            try await Self.perform(
                url: url,
                configuration: configuration,
                authorization: authorization,
                notFoundSlug: notFoundSlug
            )
        }
        inFlight[key] = task

        do {
            let data = try await task.value
            inFlight[key] = nil
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// One request, with the retry policy applied. Runs off the actor.
    private nonisolated static func perform(
        url: URL,
        configuration: DevsAppConfiguration,
        authorization: String?,
        notFoundSlug: String?
    ) async throws -> Data {
        var lastError: DevsAppError?

        for attempt in 0...configuration.maxRetries {
            if attempt > 0 {
                let delay = configuration.retryBackoff * pow(2, Double(attempt - 1))
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                try Task.checkCancellation()
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = configuration.timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let authorization {
                request.setValue(authorization, forHTTPHeaderField: "Authorization")
            }
            for (field, value) in configuration.additionalHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await configuration.transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = .network(underlying: error)
                continue
            }

            let status = response.statusCode

            // A rejected token is definitive: the same credentials keep
            // failing, so this never retries and never reaches the 404 or
            // generic branches below.
            if status == 401 || status == 403 {
                throw DevsAppError.unauthorized(
                    statusCode: status,
                    message: Self.serverMessage(in: data)
                        ?? (status == 401
                            ? "This request needs an Authorization: Bearer token."
                            : "That token is not allowed to read this.")
                )
            }

            // A 404 is a definitive answer, not a transient failure.
            if status == 404 {
                if let slug = notFoundSlug { throw DevsAppError.notFound(slug: slug) }
                throw DevsAppError.api(
                    statusCode: 404,
                    message: Self.serverMessage(in: data) ?? "Not found."
                )
            }

            if status == 429 || status >= 500 {
                lastError = .api(
                    statusCode: status,
                    message: Self.serverMessage(in: data) ?? "Server returned HTTP \(status)."
                )
                continue
            }

            guard (200..<300).contains(status) else {
                throw DevsAppError.api(
                    statusCode: status,
                    message: Self.serverMessage(in: data) ?? "Server returned HTTP \(status)."
                )
            }

            // `{"ok": false}` with a 200 is still a failure.
            if let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data),
               envelope.ok == false {
                if let slug = notFoundSlug { throw DevsAppError.notFound(slug: slug) }
                throw DevsAppError.api(
                    statusCode: status,
                    message: envelope.error ?? "Request failed."
                )
            }

            return data
        }

        throw lastError ?? .api(statusCode: nil, message: "Request to \(url) failed.")
    }

    /// Best-effort `{"ok": false, "error": "…"}` extraction, for a message
    /// worth showing someone.
    private nonisolated static func serverMessage(in data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data),
              let message = envelope.error, !message.isEmpty
        else { return nil }
        return message
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

// MARK: - Envelopes

private struct ListEnvelope: Decodable {
    let ok: Bool?
    let count: Int?
    let apps: [DevsApp]?
}

private struct DetailEnvelope: Decodable {
    let ok: Bool?
    let app: DevsApp?
}

private struct StatusEnvelope: Decodable {
    let ok: Bool?
    let error: String?
}

enum EnvelopeError: Error, CustomStringConvertible {
    case missingKey(String)

    var description: String {
        switch self {
        case .missingKey(let key):
            return "The response contained no “\(key)” value."
        }
    }
}
