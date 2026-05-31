// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "baka",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "baka",
            path: "Sources/baka",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "bakaTests",
            dependencies: ["baka"],
            path: "Tests/bakaTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
