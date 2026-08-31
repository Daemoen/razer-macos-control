// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RazerControl",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "RazerControlIPC",
            path: "Sources/RazerControlIPC"
        ),
        .executableTarget(
            name: "RazerControlInputHelper",
            dependencies: ["RazerControlIPC"],
            path: "Sources/RazerControlInputHelper",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "RazerControl",
            dependencies: ["RazerControlIPC"],
            path: "Sources/RazerControl",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "RazerControlTests",
            dependencies: ["RazerControl"],
            path: "Tests/RazerControlTests"
        )
    ]
)
