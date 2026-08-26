import Foundation

/// Store and web links for an app. Every field is optional — an app that isn't
/// published on a platform simply has no link for it.
public struct AppLinks: Codable, Hashable, Sendable {
    public let appStore: String?
    public let playStore: String?
    public let web: String?
    public let windows: String?
    public let linux: String?

    /// The app's marketing page on devsapp.app.
    public let detailPage: String?

    public init(
        appStore: String? = nil,
        playStore: String? = nil,
        web: String? = nil,
        windows: String? = nil,
        linux: String? = nil,
        detailPage: String? = nil
    ) {
        self.appStore = appStore
        self.playStore = playStore
        self.web = web
        self.windows = windows
        self.linux = linux
        self.detailPage = detailPage
    }

    public var hasAppStore: Bool { appStore != nil }
    public var hasPlayStore: Bool { playStore != nil }

    public var appStoreURL: URL? { appStore.flatMap(URL.init(string:)) }
    public var playStoreURL: URL? { playStore.flatMap(URL.init(string:)) }
    public var webURL: URL? { web.flatMap(URL.init(string:)) }
    public var detailPageURL: URL? { detailPage.flatMap(URL.init(string:)) }

    /// Which platform a link belongs to, for building a "get it on" row.
    public enum Destination: String, Sendable, CaseIterable {
        case appStore = "app_store"
        case playStore = "play_store"
        case web
        case windows
        case linux
        case detailPage = "detail_page"

        /// A label you can put on a button.
        public var title: String {
            switch self {
            case .appStore: return "App Store"
            case .playStore: return "Google Play"
            case .web: return "Web app"
            case .windows: return "Windows"
            case .linux: return "Linux"
            case .detailPage: return "devsapp.app"
            }
        }
    }

    /// Only the links that exist, in a stable order.
    public var available: [(destination: Destination, url: URL)] {
        Destination.allCases.compactMap { destination in
            guard let string = self[destination], let url = URL(string: string) else { return nil }
            return (destination, url)
        }
    }

    public subscript(destination: Destination) -> String? {
        switch destination {
        case .appStore: return appStore
        case .playStore: return playStore
        case .web: return web
        case .windows: return windows
        case .linux: return linux
        case .detailPage: return detailPage
        }
    }

    /// The best link to open for someone on `platform`, falling back to the
    /// marketing page when the app isn't on that store.
    public func primaryURL(for platform: String) -> URL? {
        let string: String?
        switch platform.lowercased() {
        case "ios", "iphone", "ipad", "mac", "macos", "visionos", "tvos":
            string = appStore ?? detailPage
        case "android":
            string = playStore ?? detailPage
        case "windows":
            string = windows ?? detailPage
        case "linux":
            string = linux ?? detailPage
        case "web":
            string = web ?? detailPage
        default:
            string = detailPage
        }
        return string.flatMap(URL.init(string:))
    }

    /// The right link for whichever platform this code is running on.
    public var primaryURLForCurrentPlatform: URL? {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS) || os(macOS)
        return primaryURL(for: "ios")
        #else
        return primaryURL(for: "web")
        #endif
    }

    private enum CodingKeys: String, CodingKey {
        case appStore = "app_store"
        case playStore = "play_store"
        case web, windows, linux
        case detailPage = "detail_page"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appStore = container.lenientOptionalString(.appStore)
        playStore = container.lenientOptionalString(.playStore)
        web = container.lenientOptionalString(.web)
        windows = container.lenientOptionalString(.windows)
        linux = container.lenientOptionalString(.linux)
        detailPage = container.lenientOptionalString(.detailPage)
    }
}
