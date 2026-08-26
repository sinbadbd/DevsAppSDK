import Foundation

/// A single store screenshot.
public struct AppScreenshot: Codable, Hashable, Sendable, Identifiable {
    /// Absolute image URL, ready for `AsyncImage`.
    public let url: String

    /// Alt text. The API currently sends an empty string for every screenshot,
    /// so use ``altText(fallback:)`` for accessibility labels.
    public let alt: String

    public var id: String { url }

    /// The URL parsed, or `nil` if the server sent something unusable.
    public var imageURL: URL? { URL(string: url) }

    public init(url: String, alt: String = "") {
        self.url = url
        self.alt = alt
    }

    /// The alt text if the API provided one, otherwise `fallback`.
    public func altText(fallback: String) -> String {
        alt.isEmpty ? fallback : alt
    }

    private enum CodingKeys: String, CodingKey {
        case url, alt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = container.lenientString(.url)
        alt = container.lenientString(.alt)
    }
}
