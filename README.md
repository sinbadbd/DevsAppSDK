# DevsAppSDK

Swift SDK for the [devsapp.app](https://devsapp.app) apps API — **list** and **detail**,
for iOS, macOS, tvOS, watchOS and visionOS.

Pure Foundation, no dependencies. The client is an `actor`, the models are
`Sendable`, and the whole package builds in Swift 6 language mode with strict
concurrency on.

```swift
let client = DevsAppClient()

let apps = try await client.listApps()                  // GET apps.php
let app = try await client.app(slug: "quickclean")      // GET apps.php?slug=…
```

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
    case .network:  show("Check your connection.")
    case .notFound: show("That app is no longer listed.")
    case .api:      show("devsapp.app is having trouble.")
    case .decoding: show("Unexpected response.")
    }
}
```

It conforms to `LocalizedError`, so `error.errorDescription` is already a
sentence you can put in front of someone.

| Case | Raised when | Carries |
| --- | --- | --- |
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
    transport: URLSessionTransport()   // or .ephemeral, or your own
))

await client.clearCache()
```

Behaviour you get without asking:

- **Cached** in memory for the TTL. A `listApps()` call also warms the detail
  cache for every app it returned.
- **Retried** on timeouts, connection failures, 429 and 5xx, with exponential
  backoff. A 404 is a definitive answer and is never retried.
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

The package's own suite does exactly that — 39 tests over parsing, caching,
filtering, coalescing, retry policy and every error path, all offline.

```bash
swift test                  # 39 tests
swift run DevsAppSmoke      # hits the live API
```

## App Transport Security

Nothing to configure: the API is HTTPS. If your app sets a restrictive
`NSAppTransportSecurity` dictionary, `devsapp.app` needs to remain reachable.

macOS apps in the App Sandbox need the outgoing-connections entitlement
(`com.apple.security.network.client`) — Xcode's "Outgoing Connections (Client)"
checkbox under Signing & Capabilities.

## The API underneath

Read-only, public, unauthenticated. Base endpoint `https://devsapp.app/api/apps.php`.

| Call | Request | Response |
| --- | --- | --- |
| List | `GET apps.php` | `200` `{"ok": true, "count": 10, "apps": [ … ]}` |
| Detail | `GET apps.php?slug=quickclean` | `200` `{"ok": true, "app": { … }}` |
| Unknown slug | `GET apps.php?slug=nope` | `404` `{"ok": false, "error": "App not found."}` |

The server sends `cache-control: public, max-age=300`, which is where the
five-minute default TTL comes from. It accepts no pagination, search or filter
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
