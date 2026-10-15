// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CoolNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CoolNotch",
            path: "Sources/CoolNotch"
        )
    ]
)
