// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniME",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MiniME",
            path: "Sources/MiniME"
        )
    ]
)
