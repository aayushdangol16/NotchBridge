// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchBridge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchBridge",
            path: "Sources/NotchBridge"
        )
    ]
)
