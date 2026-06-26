// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Syncrosa",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Syncrosa", targets: ["Syncrosa"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Syncrosa",
            dependencies: [],
            path: ".",
            sources: [
                "SyncrosaApp.swift",
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
                "Services/KeychainHelper.swift",
                "Services/USBService.swift",
                "Services/PlaylistExportService.swift",
                "Views/USBExportView.swift",
                "Views/CoversOptimizerView.swift",
                "Services/CoversOptimizerService.swift",
                "Services/LyricsService.swift",
                "Views/DuplicateFinderView.swift",
                "Views/OfflinePlaylistGeneratorView.swift"
            ],
            resources: [
                .process("AppIcon.icns")
            ],
            swiftSettings: [
                .unsafeFlags(["-emit-module", "-emit-library"]), // Encourage dynamic behavior
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
