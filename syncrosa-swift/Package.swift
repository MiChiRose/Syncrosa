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
            exclude: [
                "README.md",
                "build_arm.sh",
                "Info.plist",
                "Syncrosa.entitlements",
                "Syncrosa.xcodeproj",
                "Tests"
            ],
            sources: [
                "SyncrosaApp.swift",
                "ContentView.swift",
                "Views/SyncrosaDesignSystem.swift",
                "Views/PlaylistGeneratorView.swift",
                "Views/MediaFixerView.swift",
                "Views/FileMediaFixerView.swift",
                "Views/InfoEraserView.swift",
                "Views/IPodConverterView.swift",
                "Views/OverviewView.swift",
                "Views/RecoveryCenterView.swift",
                "Views/SafetyPreviewView.swift",
                "Views/LibraryDoctorView.swift",
                "Views/OperationHistoryView.swift",
                "Views/SettingsView.swift",
                "Views/NotificationOverlay.swift",
                "Services/MusicService.swift",
                "Services/AIService.swift",
                "Services/MetadataService.swift",
                "Services/FileMetadataService.swift",
                "Services/InfoEraserService.swift",
                "Services/IPodCompatibilityService.swift",
                "Services/SyncrosaStorage.swift",
                "Services/AppearanceService.swift",
                "Services/OperationHistoryService.swift",
                "Services/OperationRecoveryService.swift",
                "Services/LibraryToolkitService.swift",
                "Services/FolderPlaylistImportService.swift",
                "Services/MusicLibraryExchangeService.swift",
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
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "SyncrosaTests",
            dependencies: ["Syncrosa"],
            path: "Tests/SyncrosaTests",
            sources: [
                "LibraryToolkitServiceTests.swift"
            ]
        )
    ]
)
