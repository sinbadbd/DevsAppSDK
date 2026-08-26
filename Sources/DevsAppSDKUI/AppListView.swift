import DevsAppSDK
import SwiftUI

/// Integration 1 — the list.
///
/// A searchable, category-filterable list of every app, with pull-to-refresh
/// and a retryable error state. Drop it inside your own `NavigationStack`:
///
/// ```swift
/// NavigationStack {
///     AppListView(client: client)
/// }
/// ```
///
/// Or use ``DevsAppCatalogView`` to get the stack and the detail screen too.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct AppListView: View {
    @StateObject private var model: AppListModel

    /// - Parameters:
    ///   - client: The shared client. Make one and hold onto it.
    ///   - title: Navigation title for the list.
    public init(client: DevsAppClient, title: String = "Apps") {
        _model = StateObject(wrappedValue: AppListModel(client: client, title: title))
    }

    public var body: some View {
        content
            .navigationTitle(model.title)
            .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await model.load(force: true) }
            }

        case .loaded:
            listBody
                .searchable(text: $model.query, prompt: model.searchPrompt)
                .refreshable { await model.load(force: true) }
        }
    }

    private var listBody: some View {
        List {
            if !model.categories.isEmpty {
                categoryPicker
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if model.visible.isEmpty {
                Text("No apps match that search.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(model.visible) { app in
                    NavigationLink(value: app) {
                        AppRow(app: app)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: DevsApp.self) { app in
            AppDetailView(client: model.client, slug: app.slug, preloaded: app)
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "All", isSelected: model.category == nil) {
                    model.category = nil
                }
                ForEach(model.categories, id: \.self) { category in
                    CategoryChip(title: category, isSelected: model.category == category) {
                        model.category = model.category == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Row

@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct AppRow: View {
    let app: DevsApp

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(
                url: app.iconURL,
                width: 56,
                height: 56,
                cornerRadius: 13,
                label: "\(app.name) icon"
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                Text(app.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(app.category)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(app.platformSymbols, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension DevsApp {
    /// SF Symbols for the devices this app runs on.
    var platformSymbols: [String] {
        var symbols: [String] = []
        if supportsIOS { symbols.append("iphone") }
        if supportsAndroid { symbols.append("candybarphone") }
        if supportsMac { symbols.append("laptopcomputer") }
        return symbols
    }
}

// MARK: - Model

@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@MainActor
final class AppListModel: ObservableObject {
    @Published var state: LoadState<[DevsApp]> = .idle
    @Published var query: String = ""
    @Published var category: String?

    let client: DevsAppClient
    let title: String

    init(client: DevsAppClient, title: String) {
        self.client = client
        self.title = title
    }

    var all: [DevsApp] { state.value ?? [] }

    var searchPrompt: String {
        all.isEmpty ? "Search apps" : "Search \(all.count) apps"
    }

    /// Distinct categories, with combined ones split — the filter row.
    var categories: [String] {
        Array(Set(all.flatMap(\.categories))).sorted()
    }

    /// Search and category run against the loaded list, so typing costs nothing.
    var visible: [DevsApp] {
        all.filter { app in
            (category == nil || app.categories.contains(category!)) && app.matches(query)
        }
    }

    func loadIfNeeded() async {
        if case .idle = state { await load(force: false) }
    }

    func load(force: Bool) async {
        if !force { state = .loading }
        do {
            state = .loaded(try await client.listApps(forceRefresh: force))
        } catch {
            state = .failed(asDevsAppError(error))
        }
    }
}
