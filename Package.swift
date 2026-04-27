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
            dependencies: ["CCPeekCore"],
            path: "Sources/CCPeekMac"
        ),
        .executableTarget(
            name: "CCPeekMockClient",
            dependencies: ["CCPeekCore"],
            path: "Sources/CCPeekMockClient"
        ),
    ]
)
