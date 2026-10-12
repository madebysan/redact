// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Redact",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/dmrschmidt/DSWaveformImage.git", from: "14.0.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Redact",
            dependencies: [
                .product(name: "DSWaveformImage", package: "DSWaveformImage"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: [
                "Info.plist",
                "Redact.entitlements",
            ],
            resources: [
                .copy("Resources/icon.icns"),
            ],
            // The release script copies Sparkle.framework into Contents/Frameworks.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "RedactTests",
            dependencies: ["Redact"],
            path: "Tests",
            exclude: ["Acceptance/README.md", "Performance/README.md", "UI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
