// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeisterProper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MeisterProper",
            path: "Sources/MeisterProper"
        )
    ]
)
