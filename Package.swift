// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Update checks. Pinned, so a new Sparkle release never changes a build on its own.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Rules and data logic with no UI (URL handling, colors, sorting), so it can be unit tested.
        .target(name: "MagpieKit", path: "Sources/MagpieKit"),
        // The app. Everything in it runs on the main actor unless marked otherwise.
        .executableTarget(
            name: "Magpie",
            dependencies: ["MagpieKit", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Magpie",
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // build.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MagpieKitTests", dependencies: ["MagpieKit"], path: "Tests/MagpieKitTests"),
    ]
)
