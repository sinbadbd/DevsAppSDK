// Hits the live API. Run with: swift run DevsAppSmoke
import DevsAppSDK
import Foundation

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

let client = DevsAppClient()

do {
    let apps = try await client.listApps()
    print("LIST: \(apps.count) apps")
    for app in apps {
        print("  \(pad(app.slug, 14)) \(pad(app.name, 13)) v\(pad(app.version, 7)) "
              + "\(app.platforms.joined(separator: "/")) · \(app.screenshots.count) shots · \(app.category)")
    }

    guard let last = apps.last else {
        print("No apps returned — nothing else to check.")
        exit(1)
    }

    let detail = try await client.app(slug: last.slug, forceRefresh: true)
    print("\nDETAIL(\(detail.slug)): \(detail.fullName)")
    print("  minOS=\(detail.minOS) langs=\(detail.languages) iap=\(detail.hasIAP) "
          + "mac=\(detail.macSupported) year=\(detail.year)")
    print("  links=\(detail.links.available.map(\.destination.rawValue).joined(separator: ", "))")
    print("  ios=\(detail.supportsIOS) android=\(detail.supportsAndroid)")

    print("\nCATEGORIES: \(try await client.categories().joined(separator: " | "))")
    print("PLATFORMS:  \(try await client.platforms().joined(separator: " | "))")

    let android = try await client.listApps(platform: "Android").map(\.slug)
    print("ANDROID FILTER: \(android.joined(separator: ", "))")

    let search = try await client.listApps(query: "clean").map(\.slug)
    print("SEARCH \"clean\": \(search.joined(separator: ", "))")

    let missing = try await client.appIfExists(slug: "no-such-app")
    print("MISSING SLUG -> \(String(describing: missing))")

    // Second detail call for an app the list already loaded: served from cache.
    let start = Date()
    _ = try await client.app(slug: apps[0].slug)
    print(String(format: "CACHED DETAIL: %.1fms", Date().timeIntervalSince(start) * 1000))
} catch {
    print("FAILED: \(error)")
    exit(1)
}
