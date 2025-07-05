// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "claude-monitor-macos",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "claude-monitor-macos",
            targets: ["claude-monitor-macos"]
        )
    ],
    targets: [
        .executableTarget(
            name: "claude-monitor-macos",
            path: "src",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)