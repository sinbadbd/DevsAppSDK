# DevsAppSDK

Swift SDK for the [devsapp.app](https://devsapp.app) apps API — **list** and **detail**,
for iOS, macOS, tvOS, watchOS and visionOS.

Pure Foundation, no dependencies. The client is an `actor`, the models are
`Sendable`, and the whole package builds in Swift 6 language mode with strict
concurrency on.

```swift
let client = DevsAppClient(configuration: DevsAppConfiguration(token: myToken))

let apps = try await client.listApps()                  // GET apps.php
let app = try await client.app(slug: "quickclean")      // GET apps.php?slug=…
```

> **The API requires a bearer token.** Unauthenticated requests are rejected with
> `401`. See [Authentication](#authentication).

There is a companion Dart/Flutter SDK with the same shape at
`flutter/devsapp_sdk`.

## Install

**Xcode** — File ▸ Add Package Dependencies… ▸ Add Local… and pick this folder.
Then add `DevsAppSDK` to your app target (and `DevsAppSDKUI` if you want the
ready-made screens).

**Package.swift**

```swift
dependencies: [
    .package(path: "../DevsAppSDK"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "DevsAppSDK", package: "DevsAppSDK"),
    ]),
]
```

Two products ship:

| Product | Contents | Platforms |
| --- | --- | --- |
| `DevsAppSDK` | Client, models, errors. No UI. | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ |
| `DevsAppSDKUI` | SwiftUI list and detail screens. Optional. | iOS 16+, macOS 13+, visionOS 1+ |

## The client

Make **one** and hold onto it. The cache and the request coalescer live on the
instance, so a client per screen throws both away.

```swift
@main
struct MyApp: App {
    private let client = DevsAppClient()

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
        }
    }
}
```

It's an `actor`, so passing it across tasks and views is safe. There is nothing
to close.

## Authentication

Every request needs `Authorization: Bearer <token>`; the server answers `401`
without one.

```swift
let client = DevsAppClient(configuration: DevsAppConfiguration(token: myToken))
```

A raw token and an already-formed `Bearer …` value are both accepted; a blank
one is treated as no token.

### Tokens that change

For a token in the Keychain, or behind a refresh flow, pass a **provider**. It's
asked once per call (not once per retry), so a refreshed token is picked up on
the next request:

```swift
let client = DevsAppClient(configuration: DevsAppConfiguration(
    tokenProvider: { await Keychain.shared.devsappToken() }
))
```

Or set it at runtime on a client that owns its token:

```swift
await client.setToken(newToken)   // drops responses cached as the old identity
await client.setToken(nil)        // sign out
```

`setToken` is ignored when a `tokenProvider` is configured — there the provider
is the source of truth.

### When a token is rejected

```swift
do {
    let apps = try await client.listApps()
} catch let error as DevsAppError {
    if error.requiresAuthentication {
        await signInAgain()
    }
}
```

`401` and `403` are never retried: the same credentials would just fail again.
It's also why a `401` on a slug lookup surfaces as `.unauthorized` rather than
being mistaken for a missing app.

## List

```swift
let apps = try await client.listApps()

for app in apps {
    print("\(app.name) — \(app.tagline)")
    print("  \(app.category) · v\(app.version) · \(app.platforms.joined(separator: "/"))")
}
```

The API returns the whole catalogue in one response, so these filters run **on
device** against the fetched list. They don't reduce what's downloaded; they
save you writing the same `filter` closures, and let a search field run without
new requests.

```swift
try await client.listApps(category: "Utilities")   // also matches "Utilities · Privacy"
try await client.listApps(platform: "Android")     // case-insensitive
try await client.listApps(tag: "AI Cleaner")
try await client.listApps(query: "clean")          // name, tagline, description, tags
try await client.listApps(forceRefresh: true)      // skip the cache — pull-to-refresh
```

For a filter row:

```swift
try await client.categories()   // ["Developer Tools", "Finance", "Health & Fitness", …]
try await client.platforms()    // ["Android", "Mac", "iPad", "iPhone"]
```

## Detail

```swift
let app = try await client.app(slug: "quickclean")

app.fullName          // QuickClean: One-tap clean
app.description
app.minOS             // iOS 16.6+
app.links.appStoreURL // URL?
app.screenshots       // [AppScreenshot]
```

Both endpoints return identical fields, so `app(slug:)` answers from the cache a
previous `listApps()` already filled — **opening a detail screen from a list
costs no request.** Pass `forceRefresh: true` to always hit the network.

An unknown slug throws `DevsAppError.notFound`. When branching on absence reads
better than catching:

```swift
if let app = try await client.appIfExists(slug: slug) {
    show(app)
}
```

## SwiftUI, without writing the screens

Import `DevsAppSDKUI` and the whole catalogue is one view:

```swift
import DevsAppSDKUI

struct ContentView: View {
    let client: DevsAppClient

    var body: some View {
        DevsAppCatalogView(client: client)
    }
}
```

That gives you a searchable, category-filterable list with pull-to-refresh and a
retryable error state, navigating to a detail screen with a screenshot gallery
and store buttons.

### How the detail opens

Tapping a row opens the detail as a **bottom sheet** by default — it slides up
over the list, opens at half height, drags to full, and carries its own Done
button. The sheet is presented by the list itself rather than by navigation, so
nothing in the navigation hierarchy can dismiss or replace it while it is open.

```swift
DevsAppCatalogView(client: client)                            // sheet (default)
DevsAppCatalogView(client: client, detailPresentation: .push) // push instead
```

To present the sheet from your own list:

```swift
@State private var selected: DevsApp?

List(apps) { app in
    Button(app.name) { selected = app }
}
.sheet(item: $selected) { app in
    AppDetailSheet(client: client, app: app) { selected = nil }
}
```

`AppDetailSheet` takes the app you already have, so it has content on its first
frame and never opens empty.

To place the screens inside navigation you already own:

```swift
NavigationStack {
    AppListView(client: client, title: "Our apps")
}

// or, from your own row:
AppDetailView(client: client, slug: app.slug, preloaded: app)
```

`preloaded` is the app your list already holds — the detail screen renders it on
the first frame while the fetch confirms it.

## Rolling your own view

```swift
@MainActor
final class CatalogModel: ObservableObject {
    @Published private(set) var apps: [DevsApp] = []
    @Published private(set) var error: DevsAppError?

    private let client: DevsAppClient

    init(client: DevsAppClient) { self.client = client }

    func load(force: Bool = false) async {
        do {
            apps = try await client.listApps(forceRefresh: force)
            error = nil
        } catch {
            self.error = (error as? DevsAppError) ?? .network(underlying: error)
        }
    }
}
```

Then `.task { await model.load() }` on the view.

## The model

`DevsApp` maps the API one-to-one, in Swift naming.

| Property | Type | Notes |
| --- | --- | --- |
| `slug` | `String` | Identifier — pass to `app(slug:)` |
| `name` / `fullName` | `String` | Short name / store title with subtitle |
| `category` | `String` | May combine two: `Utilities · Privacy` |
| `tagline` / `description` | `String` | One-liner / full marketing copy |
| `icon` | `String` | 512px icon URL — see `iconURL` |
| `screenshots` | `[AppScreenshot]` | `url`, `alt`, `imageURL` |
| `platforms` | `[String]` | `iPhone`, `iPad`, `Mac`, `Android` |
| `tags` | `[String]` | |
| `links` | `AppLinks` | `appStore`, `playStore`, `web`, `windows`, `linux`, `detailPage` — all optional |
| `version` / `minOS` | `String` | |
| `languages` / `year` | `Int` | |
| `macSupported` / `hasIAP` | `Bool` | |

`DevsApp` is `Identifiable` by `slug` and `Hashable` over every field, which is
what SwiftUI needs: rows keep their identity across a refresh, and a changed
version still redraws.

Helpers:

```swift
app.categories               // ["Utilities", "Privacy"] — combined ones split
app.supportsIOS              // iPhone or iPad
app.supportsAndroid
app.supportsMac              // macSupported OR a "Mac" platform entry
app.hasPlatform("iphone")    // case-insensitive
app.hasTag("AI Cleaner")
app.firstScreenshot
app.matches("clean")         // the same search listApps(query:) runs
app.iconURL                  // URL?

app.links.available          // [(destination, url)] — only the ones that exist
app.links.primaryURL(for: "android")     // Play link, or the marketing page
app.links.primaryURLForCurrentPlatform   // right link for wherever this runs
```

Decoding is deliberately forgiving: a missing, null or retyped field falls back
to a safe default instead of throwing, and `"14"` still decodes as `14`. A change
on the server can't blank a list mid-scroll.

## Errors

Everything thrown is a `DevsAppError`, and `switch` over it is exhaustive.

```swift
do {
    let apps = try await client.listApps()
} catch let error as DevsAppError {
    switch error {
    case .unauthorized: await signInAgain()
    case .network:      show("Check your connection.")
    case .notFound:     show("That app is no longer listed.")
    case .api:          show("devsapp.app is having trouble.")
    case .decoding:     show("Unexpected response.")
    }
}
```

It conforms to `LocalizedError`, so `error.errorDescription` is already a
sentence you can put in front of someone.

| Case | Raised when | Carries |
| --- | --- | --- |
| `.unauthorized(statusCode:message:)` | 401/403 — no token, an expired one, or one without access | status + server message |
| `.network(underlying:)` | Offline, DNS/TLS failure, timeout — no HTTP response | the `URLError` |
| `.notFound(slug:)` | HTTP 404 | the slug |
| `.api(statusCode:message:)` | 5xx, rate limit, or `{"ok": false}` | status + server message |
| `.decoding(underlying:)` | Not the JSON shape expected | the `DecodingError` |

## Configuration

```swift
let client = DevsAppClient(configuration: DevsAppConfiguration(
    baseURL: DevsAppConfiguration.defaultBaseURL,
    timeout: 15,                       // per attempt
    cacheTTL: 300,                     // matches the server's cache-control
    maxRetries: 2,                     // 0 disables retrying
    retryBackoff: 0.3,                 // doubles each attempt
    additionalHeaders: ["X-Client": "MyApp/1.0"],
    transport: URLSessionTransport(),  // or .ephemeral, or your own
    token: myToken,                    // or tokenProvider: { await … }
))

await client.clearCache()
```

Behaviour you get without asking:

- **Cached** in memory for the TTL. A `listApps()` call also warms the detail
  cache for every app it returned.
- **Retried** on timeouts, connection failures, 429 and 5xx, with exponential
  backoff. 401, 403 and 404 are definitive answers and are never retried.
- **Dropped on identity change**: `setToken` clears the cache, so responses
  fetched as one identity are never served to another.
- **Coalesced**: identical concurrent requests share one network call, so a list
  and a detail view appearing in the same frame don't both fetch.

## Testing

`HTTPTransport` is the only seam you need. `ClosureTransport` stubs it in a line —
no `URLProtocol` subclass, no network:

```swift
let client = DevsAppClient(configuration: DevsAppConfiguration(
    transport: ClosureTransport { request in
        (fixtureData, HTTPURLResponse(url: request.url!, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!)
    }
))
```

The package's own suite does exactly that — 61 tests over parsing, caching,
filtering, coalescing, retry policy, authentication and every error path, all
offline.

```bash
swift test                  # 61 tests

# The live check needs a token; it exits 2 without one.
DEVSAPP_TOKEN=<token> swift run DevsAppSmoke
```

## App Transport Security

Nothing to configure: the API is HTTPS. If your app sets a restrictive
`NSAppTransportSecurity` dictionary, `devsapp.app` needs to remain reachable.

macOS apps in the App Sandbox need the outgoing-connections entitlement
(`com.apple.security.network.client`) — Xcode's "Outgoing Connections (Client)"
checkbox under Signing & Capabilities.

## The API underneath

Read-only, token-authenticated. Base endpoint `https://devsapp.app/api/apps.php`.

| Call | Request | Response |
| --- | --- | --- |
| List | `GET apps.php` | `200` `{"ok": true, "count": 10, "apps": [ … ]}` |
| Detail | `GET apps.php?slug=quickclean` | `200` `{"ok": true, "app": { … }}` |
| Unknown slug | `GET apps.php?slug=nope` | `404` `{"ok": false, "error": "App not found."}` |
| No token | any call without `Authorization` | `401` `{"ok": false, "error": "Missing or invalid Authorization: Bearer token."}` |

The five-minute default TTL comes from the `cache-control: public, max-age=300`
the server sent before it required auth; it now sends `cache-control: no-store`.
This SDK still keeps its short in-memory cache, since that is application state
rather than an HTTP cache — set `cacheTTL: 0` if you would rather it kept nothing. It accepts no pagination, search or filter
parameters — everything arrives in one response, which is why on-device
filtering is the right shape here rather than a compromise.

## Build status

| Platform | State |
| --- | --- |
| iOS | Built (`xcodebuild -destination 'generic/platform=iOS'`) |
| macOS | Built and tested (`swift build`, `swift test`, live smoke test) |
| tvOS / watchOS / visionOS | Declared, not built — those SDKs aren't installed in this Xcode |

## License

MIT
