// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardCloud",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ClipboardCloud",
            path: "Sources/ClipboardCloud",
            resources: [.copy("Resources/Oswald.ttf"), .copy("Resources/Oswald-OFL.txt")]
        )
    ]
)
