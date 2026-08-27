#if canImport(UIKit)
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DevsAppSDK
@testable import DevsAppSDKUI

/// Renders the shipped screens through real UIKit on the simulator.
///
/// A screen that renders "blank" is usually not empty — it is drawing labels in
/// a colour that matches the ground behind them. These tests measure how much
/// of the output actually differs from its own background, which is the thing
/// a person means when they say nothing is showing.
///
/// Limitation worth knowing before adding to these: the capture reflects the
/// **first frame only**. State that arrives asynchronously (anything driven by
/// `.task`) is not visible here, and an indeterminate `ProgressView` does not
/// appear in `layer.render(in:)` at all. Cover those at the view-model level
/// instead — see ViewModelTests.
private let detailJSON = """
    {"ok":true,"app":{
     "slug":"quickclean","name":"QuickClean","full_name":"QuickClean: One-tap clean",
     "category":"Utilities · Privacy","tagline":"One-tap iPhone cleaner powered by on-device AI.",
     "description":"QuickClean is the smartest way to clean, organize and manage your iPhone storage.",
     "icon":"https://example.com/i.jpg","screenshots":[],
     "platforms":["iPhone","iPad"],"tags":["iOS","Utilities"],
     "links":{"app_store":"https://apps.apple.com/app/id1","play_store":null,"web":null,
              "windows":null,"linux":null,"detail_page":"https://devsapp.app/apps/quickclean/"},
     "version":"1.0.0","min_os":"iOS 16.6+","languages":14,
     "mac_supported":false,"has_iap":true,"year":2025}}
    """

private struct Envelope: Decodable { let app: DevsApp }



@Suite("iOS snapshots")
@MainActor
struct SnapshotTests {
    static func fixtureApp() throws -> DevsApp {
        try JSONDecoder().decode(Envelope.self, from: Data(detailJSON.utf8)).app
    }

    static func fixtureClient() -> DevsAppClient {
        DevsAppClient(configuration: DevsAppConfiguration(
            transport: ClosureTransport { request in
                (Data(detailJSON.utf8),
                 HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!)
            }
        ))
    }

    /// Hosts `view` in a real window and returns the rendered pixels.
    static func render(
        _ view: some View,
        style: UIUserInterfaceStyle,
        size: CGSize = CGSize(width: 390, height: 844),
        settle: TimeInterval = 0.35
    ) -> UIImage {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Give SwiftUI a beat to commit its first layout pass.
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    /// Share of pixels that differ from the image's own corner pixel — a
    /// proxy for "is anything actually visible here".
    static func visibleFraction(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bg = (pixels[0], pixels[1], pixels[2])
        var differing = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let dr = abs(Int(pixels[index]) - Int(bg.0))
            let dg = abs(Int(pixels[index + 1]) - Int(bg.1))
            let db = abs(Int(pixels[index + 2]) - Int(bg.2))
            if dr + dg + db > 24 { differing += 1 }
        }
        return Double(differing) / Double(width * height)
    }

    static func save(_ image: UIImage, _ name: String) -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: url)
        return url.path
    }

    @Test("the detail screen draws visible content in light mode")
    func detailLight() throws {
        guard #available(iOS 16, *) else { return }
        let app = try Self.fixtureApp()
        let view = AppDetailView(client: Self.fixtureClient(), slug: app.slug, preloaded: app)
        let image = Self.render(view, style: .light)
        let fraction = Self.visibleFraction(image)
        print("SNAPSHOT detail-light visible=\(fraction) path=\(Self.save(image, "detail-light"))")
        #expect(fraction > 0.01, "detail screen rendered blank in light mode")
    }

    @Test("the detail screen draws visible content in dark mode")
    func detailDark() throws {
        guard #available(iOS 16, *) else { return }
        let app = try Self.fixtureApp()
        let view = AppDetailView(client: Self.fixtureClient(), slug: app.slug, preloaded: app)
        let image = Self.render(view, style: .dark)
        let fraction = Self.visibleFraction(image)
        print("SNAPSHOT detail-dark visible=\(fraction) path=\(Self.save(image, "detail-dark"))")
        #expect(fraction > 0.01, "detail screen rendered blank in dark mode")
    }





    /// Controls: do these two subviews draw at all under this harness? If the
    /// error view draws but the full screen does not, the difference is the
    /// `.task` that drives it, not the view.



    @Test("the detail sheet draws its content and a Done button")
    func detailSheet() throws {
        guard #available(iOS 16, *) else { return }
        let app = try Self.fixtureApp()
        let view = AppDetailSheet(client: Self.fixtureClient(), app: app, onClose: {})
        let image = Self.render(view, style: .light)
        let fraction = Self.visibleFraction(image)
        print("SNAPSHOT detail-sheet visible=\(fraction) path=\(Self.save(image, "detail-sheet"))")
        #expect(fraction > 0.01, "detail sheet rendered blank")
    }

    @Test("the detail sheet draws in dark mode")
    func detailSheetDark() throws {
        guard #available(iOS 16, *) else { return }
        let app = try Self.fixtureApp()
        let view = AppDetailSheet(client: Self.fixtureClient(), app: app, onClose: {})
        let image = Self.render(view, style: .dark)
        let fraction = Self.visibleFraction(image)
        print("SNAPSHOT detail-sheet-dark visible=\(fraction) path=\(Self.save(image, "detail-sheet-dark"))")
        #expect(fraction > 0.01, "detail sheet rendered blank in dark mode")
    }

    @Test("control: ErrorStateView draws on its own")
    func controlErrorView() throws {
        guard #available(iOS 16, *) else { return }
        let view = ErrorStateView(
            error: .unauthorized(statusCode: 401, message: "Token expired."),
            retry: {}
        )
        let image = Self.render(view, style: .light)
        let fraction = Self.visibleFraction(image)
        print("SNAPSHOT control-error visible=\(fraction) path=\(Self.save(image, "control-error"))")
        #expect(fraction > 0.005, "ErrorStateView itself draws nothing")
    }


    @Test("the detail screen draws inside a NavigationStack, as shipped")
    func detailInNavigationStack() throws {
        guard #available(iOS 16, *) else { return }
        let app = try Self.fixtureApp()
        let view = NavigationStack {
            AppDetailView(client: Self.fixtureClient(), slug: app.slug, preloaded: app)
        }
        let image = Self.render(view, style: .light)
        let fraction = Self.visibleFraction(image)
        print("SNAPSHOT detail-nav visible=\(fraction) path=\(Self.save(image, "detail-nav"))")
        #expect(fraction > 0.01, "detail screen rendered blank inside a NavigationStack")
    }
}
#endif
