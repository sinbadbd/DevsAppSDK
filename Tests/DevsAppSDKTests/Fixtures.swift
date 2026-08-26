import DevsAppSDK
import Foundation

/// Captured from the live API on 2026-08-21.
enum Fixtures {
    static let list = """
    {
      "ok": true,
      "count": 2,
      "apps": [
        {
          "slug": "quickclean",
          "name": "QuickClean",
          "full_name": "QuickClean: One-tap clean",
          "category": "Utilities",
          "tagline": "One-tap iPhone cleaner powered by on-device AI.",
          "description": "QuickClean is the smartest way to clean your iPhone storage.",
          "icon": "https://example.com/quickclean.jpg",
          "screenshots": [
            {"url": "https://devsapp.app/uploads/screenshots/quickclean-0.png", "alt": ""},
            {"url": "https://devsapp.app/uploads/screenshots/quickclean-1.png", "alt": ""}
          ],
          "platforms": ["iPhone", "iPad"],
          "tags": ["iOS", "Utilities", "AI Cleaner"],
          "links": {
            "app_store": "https://apps.apple.com/us/app/quickclean/id6758863743",
            "play_store": null,
            "web": null,
            "windows": null,
            "linux": null,
            "detail_page": "https://devsapp.app/apps/quickclean/"
          },
          "version": "1.0.0",
          "min_os": "iOS 16.6+",
          "languages": 14,
          "mac_supported": false,
          "has_iap": true,
          "year": 2025
        },
        {
          "slug": "sendman",
          "name": "SendMan",
          "full_name": "SendMan: API Client",
          "category": "Developer Tools",
          "tagline": "A fast API client for Android.",
          "description": "Build, send and inspect HTTP requests on the go.",
          "icon": "https://example.com/sendman.jpg",
          "screenshots": [],
          "platforms": ["Android"],
          "tags": ["Android", "Developer Tools"],
          "links": {
            "app_store": null,
            "play_store": "https://play.google.com/store/apps/details?id=app.sendman",
            "web": null,
            "windows": null,
            "linux": null,
            "detail_page": "https://devsapp.app/apps/sendman/"
          },
          "version": "2.1.0",
          "min_os": "Android 8.0+",
          "languages": 3,
          "mac_supported": false,
          "has_iap": false,
          "year": 2026
        }
      ]
    }
    """

    /// Same app as the first list entry, but a newer version and a combined
    /// category — so tests can tell a detail response from a cached list entry.
    static let detail = """
    {
      "ok": true,
      "app": {
        "slug": "quickclean",
        "name": "QuickClean",
        "full_name": "QuickClean: One-tap clean",
        "category": "Utilities · Privacy",
        "tagline": "One-tap iPhone cleaner powered by on-device AI.",
        "description": "QuickClean is the smartest way to clean your iPhone storage.",
        "icon": "https://example.com/quickclean.jpg",
        "screenshots": [{"url": "https://devsapp.app/uploads/screenshots/quickclean-0.png", "alt": ""}],
        "platforms": ["iPhone", "iPad"],
        "tags": ["iOS", "Utilities"],
        "links": {
          "app_store": "https://apps.apple.com/us/app/quickclean/id6758863743",
          "play_store": null,
          "web": null,
          "windows": null,
          "linux": null,
          "detail_page": "https://devsapp.app/apps/quickclean/"
        },
        "version": "1.0.1",
        "min_os": "iOS 16.6+",
        "languages": 14,
        "mac_supported": false,
        "has_iap": true,
        "year": 2025
      }
    }
    """

    static let notFound = #"{"ok":false,"error":"App not found."}"#
}

/// Records every URL a transport was asked for.
actor RequestLog {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }

    var count: Int { urls.count }
    var last: URL? { urls.last }
}

func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json; charset=utf-8"]
    )!
}

/// Answers list and detail requests from the fixtures, logging each call.
func fakeAPI(log: RequestLog) -> ClosureTransport {
    ClosureTransport { request in
        let url = request.url!
        await log.record(url)

        let slug = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "slug" }?
            .value

        switch slug {
        case .none, .some(""):
            return (Data(Fixtures.list.utf8), response(url, 200))
        case .some("quickclean"):
            return (Data(Fixtures.detail.utf8), response(url, 200))
        default:
            return (Data(Fixtures.notFound.utf8), response(url, 404))
        }
    }
}

/// A client wired to the fixtures, with retry delays removed.
func makeClient(
    log: RequestLog,
    cacheTTL: TimeInterval = 300,
    maxRetries: Int = 2
) -> DevsAppClient {
    DevsAppClient(configuration: DevsAppConfiguration(
        cacheTTL: cacheTTL,
        maxRetries: maxRetries,
        retryBackoff: 0,
        transport: fakeAPI(log: log)
    ))
}
