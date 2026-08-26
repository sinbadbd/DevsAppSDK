// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevsAppSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        // The client, the models and the errors. No UI, no dependencies.
        .library(name: "DevsAppSDK", targets: ["DevsAppSDK"]),
        // Optional ready-made SwiftUI list and detail screens.
        .library(name: "DevsAppSDKUI", targets: ["DevsAppSDKUI"]),
    ],
    targets: [
        .target(name: "DevsAppSDK"),
        .target(name: "DevsAppSDKUI", dependencies: ["DevsAppSDK"]),
        // Hits the live API: swift run DevsAppSmoke
        .executableTarget(name: "DevsAppSmoke", dependencies: ["DevsAppSDK"]),
        .executableTarget(name: "RenderCheck", dependencies: ["DevsAppSDK", "DevsAppSDKUI"]),
        .testTarget(name: "DevsAppSDKTests", dependencies: ["DevsAppSDK", "DevsAppSDKUI"]),
    ]
)
