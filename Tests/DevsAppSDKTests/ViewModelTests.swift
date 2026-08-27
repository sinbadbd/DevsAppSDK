import Foundation
import Testing
@testable import DevsAppSDK
@testable import DevsAppSDKUI

/// The list and detail screens are thin wrappers over these models, so testing
/// them covers the behaviour a SwiftUI preview would only show by eye.
@Suite("AppListModel")
@MainActor
struct AppListModelTests {
    @Test("loads and exposes the catalogue")
    func loads() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let log = RequestLog()
        let model = AppListModel(client: makeClient(log: log), title: "Apps")

        #expect(model.all.isEmpty)
        await model.load(force: false)

        #expect(model.all.count == 2)
        #expect(model.visible.count == 2)
        #expect(model.categories == ["Developer Tools", "Utilities"])
        #expect(model.searchPrompt == "Search 2 apps")
    }

    @Test("loadIfNeeded only loads once")
    func loadsOnce() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let log = RequestLog()
        let model = AppListModel(client: makeClient(log: log), title: "Apps")

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(await log.count == 1)
    }

    @Test("search and category filter the loaded list")
    func filters() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let model = AppListModel(client: makeClient(log: RequestLog()), title: "Apps")
        await model.load(force: false)

        model.query = "storage"
        #expect(model.visible.map(\.slug) == ["quickclean"])

        model.query = ""
        model.category = "Developer Tools"
        #expect(model.visible.map(\.slug) == ["sendman"])

        model.category = nil
        model.query = "nothing matches"
        #expect(model.visible.isEmpty)
    }


    /// The pop bug: a failed refresh used to flip `state` out of `.loaded`,
    /// which removed the list — and with it the navigationDestination that any
    /// pushed detail view depends on, popping it instantly.
    @Test func aFailedRefreshKeepsTheLoadedList() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }

        let client = makeClient(log: RequestLog(), cacheTTL: 0)
        let model = AppListModel(client: client, title: "Apps")
        await model.load(force: false)
        #expect(model.all.count == 2)

        // Now every request fails, as it would with an expired token.
        let failing = DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: 0,
            transport: ClosureTransport { request in
                (Data(#"{"ok":false,"error":"Missing or invalid Authorization: Bearer token."}"#.utf8),
                 response(request.url!, 401))
            }
        ))
        let stillLoaded = AppListModel(client: failing, title: "Apps")
        stillLoaded.state = .loaded(model.all)

        await stillLoaded.load(force: true)

        // The list survives, so the detail view stays pushed.
        guard case .loaded(let apps) = stillLoaded.state else {
            Issue.record("a failed refresh must not leave .loaded, got \(stillLoaded.state)")
            return
        }
        #expect(apps.count == 2)
        #expect(stillLoaded.refreshError?.requiresAuthentication == true)
    }

    @Test func aFailedFirstLoadStillShowsTheErrorScreen() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }

        let failing = DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: 0,
            transport: ClosureTransport { _ in throw URLError(.notConnectedToInternet) }
        ))
        let model = AppListModel(client: failing, title: "Apps")

        await model.load(force: false)

        // With nothing to show, the full-screen error is still correct.
        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(model.refreshError == nil)
    }

    @Test func aSuccessfulReloadClearsTheRefreshError() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }

        let model = AppListModel(client: makeClient(log: RequestLog(), cacheTTL: 0), title: "Apps")
        await model.load(force: false)
        model.refreshError = .network(underlying: URLError(.timedOut))

        await model.load(force: true)

        #expect(model.refreshError == nil)
        #expect(model.all.count == 2)
    }


    /// The whole point of the sheet: it belongs to the list, not to navigation,
    /// so nothing that happens to the list's state can close it.
    @Test func anOpenSheetSurvivesAFailedRefresh() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }

        let model = AppListModel(client: makeClient(log: RequestLog(), cacheTTL: 0), title: "Apps")
        await model.load(force: false)
        model.selected = model.all.first
        #expect(model.selected?.slug == "quickclean")

        // Token expires; the refresh fails.
        let failing = DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: 0,
            transport: ClosureTransport { request in
                (Data(#"{"ok":false,"error":"Missing or invalid Authorization: Bearer token."}"#.utf8),
                 response(request.url!, 401))
            }
        ))
        let stillOpen = AppListModel(client: failing, title: "Apps")
        stillOpen.state = .loaded(model.all)
        stillOpen.selected = model.all.first

        await stillOpen.load(force: true)

        #expect(stillOpen.selected?.slug == "quickclean", "the open sheet was closed by a failed refresh")
        #expect(stillOpen.refreshError?.requiresAuthentication == true)
    }

    @Test func selectingAnAppOpensTheSheet() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }

        let model = AppListModel(client: makeClient(log: RequestLog()), title: "Apps")
        await model.load(force: false)

        #expect(model.selected == nil)
        model.selected = model.all.first
        #expect(model.selected != nil)
        model.selected = nil
        #expect(model.selected == nil)
    }

    @Test("a failed load lands in .failed with a usable message")
    func failure() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: 0,
            transport: ClosureTransport { _ in throw URLError(.notConnectedToInternet) }
        ))
        let model = AppListModel(client: client, title: "Apps")

        await model.load(force: false)

        guard case .failed(let error) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(error.errorDescription?.isEmpty == false)
        #expect(model.visible.isEmpty)
    }
}

@Suite("AppDetailModel")
@MainActor
struct AppDetailModelTests {
    private func listApp() async throws -> DevsApp {
        let apps = try await makeClient(log: RequestLog()).listApps()
        return try #require(apps.first)
    }

    @Test("fetches the app for its slug")
    func fetches() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let model = AppDetailModel(
            client: makeClient(log: RequestLog()),
            slug: "quickclean",
            preloaded: nil
        )

        #expect(model.app == nil)
        await model.load(force: false)

        #expect(model.app?.slug == "quickclean")
        #expect(model.app?.version == "1.0.1")
    }

    @Test("renders the preloaded app before the fetch lands")
    func preloadedRendersFirst() async throws {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let preloaded = try await listApp()
        let model = AppDetailModel(
            client: makeClient(log: RequestLog()),
            slug: preloaded.slug,
            preloaded: preloaded
        )

        // Available on the very first frame, with no load having run.
        #expect(model.app?.slug == "quickclean")
        #expect(model.app?.version == "1.0.0")

        await model.load(force: true)
        #expect(model.app?.version == "1.0.1") // the fetch then supersedes it
    }

    @Test("an unknown slug lands in .failed with a not-found message")
    func unknownSlug() async {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let model = AppDetailModel(
            client: makeClient(log: RequestLog()),
            slug: "does-not-exist",
            preloaded: nil
        )

        await model.load(force: false)

        guard case .failed(let error) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        guard case .notFound(let slug) = error else {
            Issue.record("expected .notFound, got \(error)")
            return
        }
        #expect(slug == "does-not-exist")
        #expect(model.app == nil) // so the view shows the error, not a blank page
    }

    @Test("keeps showing the preloaded app when the refresh fails")
    func keepsPreloadedOnFailure() async throws {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let preloaded = try await listApp()
        let client = DevsAppClient(configuration: DevsAppConfiguration(
            maxRetries: 0,
            transport: ClosureTransport { _ in throw URLError(.timedOut) }
        ))
        let model = AppDetailModel(client: client, slug: preloaded.slug, preloaded: preloaded)

        await model.load(force: true)

        // A dropped connection shouldn't blank a page that already has content.
        #expect(model.app?.slug == "quickclean")
    }

    @Test("opening detail after a list load costs no request")
    func servedFromCache() async throws {
        guard #available(iOS 16, macOS 13, visionOS 1, *) else { return }
        let log = RequestLog()
        let client = makeClient(log: log)
        _ = try await client.listApps()

        let model = AppDetailModel(client: client, slug: "quickclean", preloaded: nil)
        await model.load(force: false)

        #expect(model.app?.slug == "quickclean")
        #expect(await log.count == 1)
    }
}
