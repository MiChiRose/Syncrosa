// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iGeniusAI-arm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "iGeniusAI-arm", targets: ["iGeniusAI-arm"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "iGeniusAI-arm",
            dependencies: [],
            path: ".",
            sources: [
                "iGeniusAI-armApp.swift",
                "ContentView.swift",
                "Views/PlaylistGeneratorView.swift",
                "Views/MediaFixerView.swift",
                "Views/FileMediaFixerView.swift",
                "Views/SettingsView.swift",
                "Views/NotificationOverlay.swift",
                "Services/MusicService.swift",
                "Services/AIService.swift",
                "Services/MetadataService.swift",
                "Services/FileMetadataService.swift",
                "Services/LocalizationService.swift",
                "Services/KeychainHelper.swift"
            ],
            resources: [
                .process("genius_atom.icns")
            ],
            swiftSettings: [
                .unsafeFlags(["-emit-module", "-emit-library"]), // Encourage dynamic behavior
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
