// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iGenius_ARM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "iGenius_ARM", targets: ["iGenius_ARM"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "iGenius_ARM",
            dependencies: [],
            path: ".",
            sources: [
                "iGenius_ARMApp.swift",
                "ContentView.swift",
                "Views/PlaylistGeneratorView.swift",
                "Views/MediaFixerView.swift",
                "Views/FileMediaFixerView.swift",
                "Views/SettingsView.swift",
                "Views/NotificationOverlay.swift",
                "Services/MusicService.swift",
                "Services/AIService.swift",
                "Services/MetadataService.swift"
            ],
            swiftSettings: [
                .unsafeFlags(["-emit-module", "-emit-library"]), // Encourage dynamic behavior
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
