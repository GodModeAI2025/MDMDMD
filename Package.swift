// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Skriptum",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "SkriptumCore", targets: ["SkriptumCore"]),
        .library(name: "SkriptumAI", targets: ["SkriptumAI"]),
        .library(name: "SkriptumExport", targets: ["SkriptumExport"]),
        .library(name: "SkriptumAuth", targets: ["SkriptumAuth"]),
        .library(name: "SkriptumBlocks", targets: ["SkriptumBlocks"]),
        .library(name: "SkriptumWritingQuality", targets: ["SkriptumWritingQuality"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")
    ],
    targets: [
        .target(name: "SkriptumCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "SkriptumAI", dependencies: ["SkriptumAuth"]),
        .target(name: "SkriptumAuth"),
        .target(name: "SkriptumBlocks", dependencies: ["SkriptumCore", .product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "SkriptumWorkspaceModel", dependencies: ["SkriptumCore", "SkriptumExport"], path: "Sources", sources: ["SkriptumApp/WritingLibrary.swift", "SkriptumApp/RecoveredDraftModels.swift", "SkriptumApp/WorkspaceFileTypes.swift", "SkriptumApp/WritingNavigation.swift", "SkriptumPageTools/LibraryPageTools.swift", "SkriptumPageTools/WorkflowSupport.swift", "SkriptumPageTools/BlockMutation.swift", "SkriptumPageTools/WritingPreferencesStorage.swift"]),
        .target(name: "SkriptumWritingQuality", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "Modules/SkriptumWritingQuality/Sources/SkriptumWritingQuality"),
        .target(name: "SkriptumExport", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "SkriptumCoreTests", dependencies: ["SkriptumCore"]),
        .testTarget(name: "SkriptumWorkspaceModelTests", dependencies: ["SkriptumWorkspaceModel", "SkriptumCore"]),
        .testTarget(name: "SkriptumAITests", dependencies: ["SkriptumAI", "SkriptumCore"]),
        .testTarget(name: "SkriptumExportTests", dependencies: ["SkriptumExport"]),
        .testTarget(name: "SkriptumAuthTests", dependencies: ["SkriptumAuth"]),
        .testTarget(name: "SkriptumBlocksTests", dependencies: ["SkriptumBlocks"]),
        .testTarget(name: "SkriptumWritingQualityTests", dependencies: ["SkriptumWritingQuality", "SkriptumExport"], path: "Modules/SkriptumWritingQuality/Tests/SkriptumWritingQualityTests")
    ]
)
