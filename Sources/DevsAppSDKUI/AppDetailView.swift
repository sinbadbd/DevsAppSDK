import DevsAppSDK
import SwiftUI

/// Integration 2 — the detail.
///
/// Pass the app the list already holds as `preloaded` and the screen renders on
/// the first frame while the detail call confirms it.
///
/// ```swift
/// AppDetailView(client: client, slug: app.slug, preloaded: app)
/// ```
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct AppDetailView: View {
    @StateObject private var model: AppDetailModel

    /// - Parameters:
    ///   - client: The shared client.
    ///   - slug: Which app to show.
    ///   - preloaded: An app you already have, painted until the fetch lands.
    public init(client: DevsAppClient, slug: String, preloaded: DevsApp? = nil) {
        _model = StateObject(
            wrappedValue: AppDetailModel(client: client, slug: slug, preloaded: preloaded)
        )
    }

    public var body: some View {
        Group {
            if let app = model.app {
                loaded(app)
            } else if case .failed(let error) = model.state {
                ErrorStateView(error: error) {
                    Task { await model.load(force: true) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(platformBackground)
        .navigationTitle(model.app?.name ?? "")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.loadIfNeeded() }
    }

    private func loaded(_ app: DevsApp) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(app)
                storeButtons(app)
                if app.hasScreenshots { screenshots(app) }
                facts(app)
                about(app)
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ app: DevsApp) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RemoteImage(
                url: app.iconURL,
                width: 88,
                height: 88,
                cornerRadius: 20,
                label: "\(app.name) icon"
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(app.fullName)
                    .font(.title3.weight(.semibold))
                Text(app.category)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                Text("Version \(app.version) · \(app.minOS)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func storeButtons(_ app: DevsApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.tagline)
                .font(.body)

            HStack(spacing: 12) {
                ForEach(app.links.available.filter { $0.destination != .detailPage }, id: \.url) { link in
                    Link(destination: link.url) {
                        Label(link.destination.title, systemImage: symbol(for: link.destination))
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let page = app.links.detailPageURL {
                    Link(destination: page) {
                        Label("More", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func screenshots(_ app: DevsApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screenshots")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(app.screenshots.enumerated()), id: \.element.id) { index, shot in
                        RemoteImage(
                            url: shot.imageURL,
                            width: 180,
                            height: 380,
                            cornerRadius: 18,
                            label: shot.altText(fallback: "\(app.name) screenshot \(index + 1)")
                        )
                    }
                }
            }
        }
    }

    private func facts(_ app: DevsApp) -> some View {
        FlowRow(spacing: 8) {
            ForEach(app.platforms, id: \.self) { Pill(text: $0) }
            if app.hasIAP { Pill(text: "In-app purchases") }
            Pill(text: "\(app.languages) languages")
            Pill(text: String(app.year))
        }
    }

    private func about(_ app: DevsApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
            Text(app.description)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !app.tags.isEmpty {
                Text(app.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private func symbol(for destination: AppLinks.Destination) -> String {
        switch destination {
        case .appStore: return "apple.logo"
        case .playStore: return "play.rectangle"
        case .web: return "globe"
        case .windows: return "pc"
        case .linux: return "terminal"
        case .detailPage: return "safari"
        }
    }
}

// MARK: - Small pieces

@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.quaternary))
    }
}

/// Wraps its children onto new lines when they run out of width.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var total = CGSize.zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            total.width = max(total.width, origin.x - spacing)
        }
        total.height = origin.y + rowHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Model

@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@MainActor
final class AppDetailModel: ObservableObject {
    @Published var state: LoadState<DevsApp> = .idle

    private let client: DevsAppClient
    private let slug: String
    private let preloaded: DevsApp?

    init(client: DevsAppClient, slug: String, preloaded: DevsApp?) {
        self.client = client
        self.slug = slug
        self.preloaded = preloaded
    }

    /// The fetched app, or the one the list handed over until it arrives.
    var app: DevsApp? { state.value ?? preloaded }

    func loadIfNeeded() async {
        if case .idle = state { await load(force: false) }
    }

    func load(force: Bool) async {
        if preloaded == nil, !force { state = .loading }
        do {
            state = .loaded(try await client.app(slug: slug, forceRefresh: force))
        } catch {
            state = .failed(asDevsAppError(error))
        }
    }
}
