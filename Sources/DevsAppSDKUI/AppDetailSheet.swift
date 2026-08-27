import DevsAppSDK
import SwiftUI

/// An app's detail presented as a bottom sheet.
///
/// Use it when you want the detail to open over the list rather than pushing
/// onto a navigation stack:
///
/// ```swift
/// .sheet(item: $selected) { app in
///     AppDetailSheet(client: client, app: app) { selected = nil }
/// }
/// ```
///
/// ``AppListView`` does this for you by default — see ``DetailPresentation``.
///
/// It opens at half height and can be dragged to full, carries its own close
/// button, and is presented by whoever owns the list, so nothing in the
/// navigation hierarchy can dismiss or replace it while it is open.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct AppDetailSheet: View {
    private let client: DevsAppClient
    private let app: DevsApp
    private let onClose: () -> Void

    /// - Parameters:
    ///   - client: The shared client.
    ///   - app: The app to show. It is handed straight to the detail view, so
    ///     the sheet has content on its first frame and never opens empty.
    ///   - onClose: Called when the person taps Done.
    public init(client: DevsAppClient, app: DevsApp, onClose: @escaping () -> Void) {
        self.client = client
        self.app = app
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            AppDetailView(client: client, slug: app.slug, preloaded: app)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
