// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "cc-peek-monorepo",
    defaultLocalization: "zh-Hans",
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
                "Sparkle",
            ],
            path: "Sources/CCPeekMac",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CCPeekMockClient",
            dependencies: ["CCPeekCore"],
            path: "Sources/CCPeekMockClient"
        ),
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "9fec2b888e6e2940b1bfbd5d3d010b9f67076b52170923549095cbb74132403b"
        ),
    ]
)
