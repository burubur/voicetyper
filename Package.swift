// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "VoiceTyper",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Using `fast` branch for -O3 optimization in Debug builds
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "fast")
    ],
    targets: [
        .executableTarget(
            name: "VoiceTyper",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            path: "Sources/VoiceTyper"
        ),
    ]
)
