// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cc-peek",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CCPeekCore", targets: ["CCPeekCore"]),
        .executable(name: "CCPeekHook", targets: ["CCPeekHook"]),
        .executable(name: "CCPeekMac", targets: ["CCPeekMac"]),
        .executable(name: "CCPeekMockClient", targets: ["CCPeekMockClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "CCPeekCore",
            path: "Sources/CCPeekCore"
        ),
        .executableTarget(
            name: "CCPeekHook",
            dependencies: ["CCPeekCore"],
            path: "Sources/CCPeekHook"
        ),
        .executableTarget(
            name: "CCPeekMac",
            dependencies: [
                "CCPeekCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/CCPeekMac"
        ),
        .executableTarget(
            name: "CCPeekMockClient",
            dependencies: ["CCPeekCore"],
            path: "Sources/CCPeekMockClient"
        ),
    ]
)
