import Foundation

/// An app published on devsapp.app.
///
/// The list and detail endpoints return the same fields, so one type serves
/// both — a row in a list can be handed straight to a detail screen.
public struct DevsApp: Codable, Hashable, Sendable, Identifiable {
    /// Stable identifier, and the value to pass to ``DevsAppClient/app(slug:forceRefresh:)``.
    public let slug: String

    /// Short display name — *QuickClean*.
    public let name: String

    /// Store title including the subtitle — *QuickClean: One-tap clean*.
    public let fullName: String

    /// Store category. May combine two with a middle dot, e.g.
    /// *Utilities · Privacy* — see ``categories``.
    public let category: String

    /// One-line pitch, sized for a list subtitle.
    public let tagline: String

    /// Full marketing copy, for a detail screen.
    public let description: String

    /// 512px app icon URL.
    public let icon: String

    public let screenshots: [AppScreenshot]

    /// Supported devices as published: `iPhone`, `iPad`, `Mac`, `Android`.
    public let platforms: [String]

    public let tags: [String]

    public let links: AppLinks

    /// Latest released version — *1.0.0*.
    public let version: String

    /// Minimum OS as published — *iOS 16.6+*.
    public let minOS: String

    /// Number of localizations.
    public let languages: Int

    public let macSupported: Bool

    /// Whether the app offers in-app purchases.
    public let hasIAP: Bool

    /// Release year.
    public let year: Int

    public var id: String { slug }

    public var iconURL: URL? { URL(string: icon) }

    /// ``category`` split into its parts, so *Utilities · Privacy* becomes
    /// `["Utilities", "Privacy"]`.
    public var categories: [String] {
        category
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var supportsIPhone: Bool { hasPlatform("iPhone") }
    public var supportsIPad: Bool { hasPlatform("iPad") }
    public var supportsAndroid: Bool { hasPlatform("Android") }
    public var supportsIOS: Bool { supportsIPhone || supportsIPad }

    /// True when the app ships for the Mac, whether that's published as a
    /// platform entry or only as the `mac_supported` flag.
    public var supportsMac: Bool { macSupported || hasPlatform("Mac") }

    /// Case-insensitive check against ``platforms``.
    public func hasPlatform(_ platform: String) -> Bool {
        platforms.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
    }

    /// Case-insensitive check against ``tags``.
    public func hasTag(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    public var hasScreenshots: Bool { !screenshots.isEmpty }
    public var firstScreenshot: AppScreenshot? { screenshots.first }

    /// Whether this app matches free text across its name, tagline,
    /// description, category and tags. This is the search
    /// ``DevsAppClient/listApps(category:platform:tag:query:forceRefresh:)``
    /// runs for its `query` argument.
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        func has(_ value: String) -> Bool { value.lowercased().contains(needle) }
        return has(name) || has(fullName) || has(slug) || has(tagline)
            || has(description) || has(category) || tags.contains(where: has)
    }

    public init(
        slug: String,
        name: String,
        fullName: String,
        category: String,
        tagline: String,
        description: String,
        icon: String,
        screenshots: [AppScreenshot],
        platforms: [String],
        tags: [String],
        links: AppLinks,
        version: String,
        minOS: String,
        languages: Int,
        macSupported: Bool,
        hasIAP: Bool,
        year: Int
    ) {
        self.slug = slug
        self.name = name
        self.fullName = fullName
        self.category = category
        self.tagline = tagline
        self.description = description
        self.icon = icon
        self.screenshots = screenshots
        self.platforms = platforms
        self.tags = tags
        self.links = links
        self.version = version
        self.minOS = minOS
        self.languages = languages
        self.macSupported = macSupported
        self.hasIAP = hasIAP
        self.year = year
    }

    private enum CodingKeys: String, CodingKey {
        case slug, name, category, tagline, description, icon
        case screenshots, platforms, tags, links, version, languages, year
        case fullName = "full_name"
        case minOS = "min_os"
        case macSupported = "mac_supported"
        case hasIAP = "has_iap"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = container.lenientString(.slug)
        name = container.lenientString(.name)
        fullName = container.lenientString(.fullName)
        category = container.lenientString(.category)
        tagline = container.lenientString(.tagline)
        description = container.lenientString(.description)
        icon = container.lenientString(.icon)
        screenshots = container.lenientArray(AppScreenshot.self, .screenshots)
        platforms = container.lenientStringArray(.platforms)
        tags = container.lenientStringArray(.tags)
        links = container.lenientValue(AppLinks.self, .links, default: AppLinks())
        version = container.lenientString(.version)
        minOS = container.lenientString(.minOS)
        languages = container.lenientInt(.languages)
        macSupported = container.lenientBool(.macSupported)
        hasIAP = container.lenientBool(.hasIAP)
        year = container.lenientInt(.year)
    }
}

// `description` already holds the app's marketing copy, so the printable
// summary goes on the debug side rather than shadowing it.
extension DevsApp: CustomDebugStringConvertible {
    public var debugDescription: String { "DevsApp(\(slug), \(name), v\(version))" }
}
