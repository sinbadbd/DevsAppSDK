import DevsAppSDK
import SwiftUI

/// The whole catalogue — list, navigation and detail — in one view.
///
/// ```swift
/// struct ContentView: View {
///     private let client = DevsAppClient()
///
///     var body: some View {
///         DevsAppCatalogView(client: client)
///     }
/// }
/// ```
///
/// Reach for ``AppListView`` and ``AppDetailView`` directly when you need the
/// screens inside navigation you already own.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct DevsAppCatalogView: View {
    private let client: DevsAppClient
    private let title: String

    public init(client: DevsAppClient = DevsAppClient(), title: String = "Apps") {
        self.client = client
        self.title = title
    }

    public var body: some View {
        NavigationStack {
            AppListView(client: client, title: title)
        }
    }
}
