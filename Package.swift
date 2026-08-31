// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RazerControl",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "RazerControlInputHelper",
            path: "Sources/RazerControlInputHelper",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "RazerControl",
            path: "Sources/RazerControl",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "RazerControlTests",
            dependencies: ["RazerControl"],
            path: "Tests/RazerControlTests"
        )
    ]
)
