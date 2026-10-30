// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "TouchScope",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TouchScope",
            path: "Sources/TouchScope",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
