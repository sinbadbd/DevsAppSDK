import Foundation
import Testing
@testable import DevsAppSDK

@Suite("DevsApp")
struct DevsAppTests {
    private func firstApp() throws -> DevsApp {
        struct Envelope: Decodable { let apps: [DevsApp] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(Fixtures.list.utf8))
        return try #require(envelope.apps.first)
    }

    private func decode(_ json: String) throws -> DevsApp {
        try JSONDecoder().decode(DevsApp.self, from: Data(json.utf8))
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        let app = try firstApp()
        let encoded = try JSONEncoder().encode(app)
        let again = try JSONDecoder().decode(DevsApp.self, from: encoded)

        #expect(again == app)
    }

    @Test("survives missing and mistyped fields")
    func lenient() throws {
        let app = try decode("""
        {
          "slug": "partial",
          "languages": "7",
          "has_iap": "true",
          "platforms": ["iPhone", null, "iPad"],
          "screenshots": "not-a-list",
          "links": null
        }
        """)

        #expect(app.slug == "partial")
        #expect(app.name.isEmpty)
        #expect(app.languages == 7)          // "7" coerced
        #expect(app.hasIAP)                  // "true" coerced
        #expect(app.platforms == ["iPhone", "iPad"])  // null dropped
        #expect(app.screenshots.isEmpty)     // wrong type ignored
        #expect(app.links.available.isEmpty)
        #expect(app.year == 0)
    }

    @Test("splits combined categories")
    func combinedCategory() throws {
        let app = try decode(#"{"category": "Utilities · Privacy"}"#)
        #expect(app.categories == ["Utilities", "Privacy"])
    }

    @Test("platform and tag checks are case-insensitive")
    func caseInsensitive() throws {
        let app = try firstApp()
        #expect(app.hasPlatform("iphone"))
        #expect(app.hasTag("ai cleaner"))
        #expect(!app.hasPlatform("Android"))
        #expect(!app.supportsMac)
    }

    @Test("mac_supported implies Mac support without a platform entry")
    func macFlag() throws {
        let app = try decode(#"{"platforms": ["iPhone"], "mac_supported": true}"#)
        #expect(app.supportsMac)
    }

    @Test("matches() searches every text field")
    func search() throws {
        let app = try firstApp()
        #expect(app.matches("QUICK"))
        #expect(app.matches("storage"))
        #expect(app.matches("ai cleaner"))
        #expect(app.matches(""))
        #expect(!app.matches("spreadsheet"))
    }

    @Test("is Identifiable by slug but Equatable on the whole record")
    func identity() throws {
        struct Envelope: Decodable { let app: DevsApp }
        let fromList = try firstApp()
        let fromDetail = try JSONDecoder()
            .decode(Envelope.self, from: Data(Fixtures.detail.utf8)).app

        #expect(fromList.id == fromDetail.id)  // same slug, so SwiftUI keeps the row
        #expect(fromList != fromDetail)        // newer version, so SwiftUI redraws it
    }
}

@Suite("AppLinks")
struct AppLinksTests {
    private func links() throws -> AppLinks {
        struct Envelope: Decodable { let apps: [DevsApp] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(Fixtures.list.utf8))
        return try #require(envelope.apps.first).links
    }

    @Test("exposes only the links that exist")
    func available() throws {
        let links = try links()
        #expect(links.available.map(\.destination) == [.appStore, .detailPage])
        #expect(links.hasAppStore)
        #expect(!links.hasPlayStore)
        #expect(links.appStoreURL != nil)
        #expect(links.playStoreURL == nil)
    }

    @Test("primaryURL picks the right store per platform")
    func primary() throws {
        let links = try links()
        #expect(links.primaryURL(for: "ios")?.host == "apps.apple.com")
        #expect(links.primaryURL(for: "iPad")?.host == "apps.apple.com")
        // No Play listing, so it falls back to the marketing page.
        #expect(links.primaryURL(for: "android")?.host == "devsapp.app")
        #expect(links.primaryURL(for: "haiku-os")?.host == "devsapp.app")
    }

    @Test("destination titles are button-ready")
    func titles() {
        #expect(AppLinks.Destination.appStore.title == "App Store")
        #expect(AppLinks.Destination.playStore.title == "Google Play")
    }
}

@Suite("AppScreenshot")
struct AppScreenshotTests {
    @Test("altText falls back when the API sends an empty alt")
    func altFallback() throws {
        struct Envelope: Decodable { let apps: [DevsApp] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(Fixtures.list.utf8))
        let shot = try #require(envelope.apps.first?.firstScreenshot)

        #expect(shot.alt.isEmpty)
        #expect(shot.altText(fallback: "QuickClean screenshot") == "QuickClean screenshot")
        #expect(shot.imageURL != nil)
    }
}

@Suite("TTLCache")
struct TTLCacheTests {
    @Test("expires entries once the TTL has passed")
    func expiry() {
        var cache = TTLCache<String, Int>(ttl: 60)
        let now = Date()

        cache.insert(1, for: "a", now: now)
        #expect(cache.value(for: "a", now: now.addingTimeInterval(59)) == 1)
        #expect(cache.value(for: "a", now: now.addingTimeInterval(61)) == nil)
    }

    @Test("a zero TTL stores nothing")
    func zeroTTL() {
        var cache = TTLCache<String, Int>(ttl: 0)
        cache.insert(1, for: "a")
        #expect(cache.value(for: "a") == nil)
        #expect(cache.count == 0)
    }
}
