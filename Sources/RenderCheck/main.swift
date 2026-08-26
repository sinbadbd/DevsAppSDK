// Temporary diagnostic: renders AppDetailView offscreen to a PNG so its layout
// can be inspected without a device.
import AppKit
import DevsAppSDK
import SwiftUI
@testable import DevsAppSDKUI

let json = """
{"ok":true,"app":{
 "slug":"quickclean","name":"QuickClean","full_name":"QuickClean: One-tap clean",
 "category":"Utilities · Privacy","tagline":"One-tap iPhone cleaner powered by on-device AI.",
 "description":"QuickClean is the smartest way to clean, organize and manage your iPhone storage. Every byte of analysis happens on your phone.",
 "icon":"https://example.com/i.jpg",
 "screenshots":[],
 "platforms":["iPhone","iPad"],"tags":["iOS","Utilities","AI Cleaner"],
 "links":{"app_store":"https://apps.apple.com/app/id1","play_store":null,"web":null,
          "windows":null,"linux":null,"detail_page":"https://devsapp.app/apps/quickclean/"},
 "version":"1.0.0","min_os":"iOS 16.6+","languages":14,
 "mac_supported":false,"has_iap":true,"year":2025}}
"""

struct Envelope: Decodable { let app: DevsApp }

@available(macOS 13, *)
@MainActor
func render(to path: String) throws {
    let app = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).app

    let client = DevsAppClient(configuration: DevsAppConfiguration(
        transport: ClosureTransport { request in
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                              httpVersion: nil, headerFields: nil)!)
        }
    ))

    let which = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "detail"

    let view: AnyView
    switch which {
    case "control":
        view = AnyView(VStack {
            Text("CONTROL RENDERS").font(.largeTitle)
            Text(app.fullName)
        })
    case "flowrow":
        view = AnyView(FlowRow(spacing: 8) {
            ForEach(app.platforms, id: \.self) { Pill(text: $0) }
            Pill(text: "In-app purchases")
            Pill(text: "14 languages")
        })
    case "pieces":
        // The detail body's parts, rebuilt outside AppDetailView.
        view = AnyView(ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(app.fullName).font(.title3.weight(.semibold))
                Text(app.tagline)
                Text("About").font(.headline)
                Text(app.description).font(.callout)
            }
            .padding(20)
        })
    default:
        view = AnyView(AppDetailView(client: client, slug: app.slug, preloaded: app))
    }

    let framed = view
        .frame(width: 390, height: 844)
        .background(Color.white)

    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        print("RENDER FAILED")
        exit(1)
    }

    try png.write(to: URL(fileURLWithPath: path))
    print("rendered \(Int(image.size.width))x\(Int(image.size.height)) -> \(path)")
}

if #available(macOS 13, *) {
    try render(to: CommandLine.arguments[1])
} else {
    print("needs macOS 13")
}
