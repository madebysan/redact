// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Redact",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/dmrschmidt/DSWaveformImage.git", from: "14.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Redact",
            dependencies: [
                .product(name: "DSWaveformImage", package: "DSWaveformImage"),
            ],
            path: "Sources",
            exclude: [
                "Info.plist",
                "Redact.entitlements",
            ],
            resources: [
                .copy("Resources/icon.icns"),
                .copy("Resources/whisper-transcribe.py"),
            ]
        ),
        .testTarget(
            name: "RedactTests",
            dependencies: ["Redact"],
            path: "Tests"
        ),
    ]
)
