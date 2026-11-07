// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no UI (URL handling, colors, sorting), so it can be unit tested.
        .target(name: "MagpieKit", path: "Sources/MagpieKit"),
        // The app. Everything in it runs on the main actor unless marked otherwise.
        .executableTarget(
            name: "Magpie",
            dependencies: ["MagpieKit"],
            path: "Sources/Magpie",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "MagpieKitTests", dependencies: ["MagpieKit"], path: "Tests/MagpieKitTests"),
    ]
)
