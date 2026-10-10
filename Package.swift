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
        .library(name: "SkriptumWritingQuality", targets: ["SkriptumWritingQuality"]),
        .library(name: "SkriptumWorkspaceClient", targets: ["SkriptumWorkspaceClient"]),
        .library(name: "SkriptumScheduling", targets: ["SkriptumScheduling"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/apple/foundation-models-utilities.git", revision: "cc3820def1fe016bc6cd49d958cd2f2a29be76a8")
    ],
    targets: [
        .target(name: "SkriptumCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "SkriptumAI", dependencies: ["SkriptumAuth", .product(name: "FoundationModelsUtilities", package: "foundation-models-utilities")], resources: [.copy("Resources/FoundationModelsUtilitiesLicense.txt")]),
        .target(name: "SkriptumAuth", dependencies: ["SkriptumWorkspaceClient"]),
        .target(name: "SkriptumWorkspaceClient", path: "Modules/SkriptumWorkspaceClient/Sources/SkriptumWorkspaceClient"),
        .target(name: "SkriptumBlocks", dependencies: ["SkriptumCore", .product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "SkriptumScheduling", path: "Modules/SkriptumScheduling/Sources/SkriptumScheduling"),
        .target(name: "SkriptumWorkspaceModel", dependencies: ["SkriptumCore", "SkriptumExport", "SkriptumWorkspaceClient", "SkriptumScheduling", "SkriptumAI"], path: "Sources", exclude: ["SkriptumApp/Settings.bundle"], sources: ["SkriptumApp/WritingLibrary.swift", "SkriptumApp/ICloudSyncEngine.swift", "SkriptumApp/ICloudChangeHints.swift", "SkriptumApp/ICloudForegroundRefresh.swift", "SkriptumApp/ICloudShareRecordBuilder.swift", "SkriptumApp/ICloudShareOwnerTransport.swift", "SkriptumApp/ICloudShareParticipantTransport.swift", "SkriptumApp/ICloudSharedSnapshotReceiver.swift", "SkriptumApp/ICloudSharedChangeSender.swift", "SkriptumApp/ICloudSharedSession.swift", "SkriptumApp/ICloudSharedCatalog.swift", "SkriptumApp/ICloudPageConflict.swift", "SkriptumApp/LocalScheduleAuthority.swift", "SkriptumApp/LocalScheduleDispatcher.swift", "SkriptumApp/ScheduledAIExecutor.swift", "SkriptumApp/LocalScheduleSession.swift", "SkriptumApp/ICloudLibrarySession.swift", "SkriptumApp/RecoveredDraftModels.swift", "SkriptumApp/WorkspaceFileTypes.swift", "SkriptumApp/WritingNavigation.swift", "SkriptumApp/WorkspaceWindowRegistry.swift", "SkriptumApp/CloudConnectionRegistry.swift", "SkriptumApp/WorkspaceDeploymentConfiguration.swift", "SkriptumApp/WorkspaceAccountState.swift", "SkriptumApp/WorkspaceAccountCoordinator.swift", "SkriptumApp/WorkspaceSystemContainerRoots.swift", "SkriptumApp/WorkspaceAccountPresentation.swift", "SkriptumApp/WorkspaceLibraryDiscoveryAccess.swift", "SkriptumApp/WorkspaceLibraryPickerPresentation.swift", "SkriptumApp/WorkspaceLibraryPickerCoordinator.swift", "SkriptumApp/WorkspaceAccountRuntime.swift", "SkriptumApp/WorkspaceDeploymentBundleLoader.swift", "SkriptumPageTools/LibraryPageTools.swift", "SkriptumPageTools/WorkflowSupport.swift", "SkriptumPageTools/BlockMutation.swift", "SkriptumPageTools/WritingPreferencesStorage.swift", "SkriptumPageTools/EditorNotification.swift"]),
        .target(name: "SkriptumWritingQuality", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "Modules/SkriptumWritingQuality/Sources/SkriptumWritingQuality"),
        .target(name: "SkriptumExport", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "SkriptumCoreTests", dependencies: ["SkriptumCore"]),
        .testTarget(name: "SkriptumSchedulingTests", dependencies: ["SkriptumScheduling"], path: "Modules/SkriptumScheduling/Tests/SkriptumSchedulingTests"),
        .testTarget(name: "SkriptumWorkspaceModelTests", dependencies: ["SkriptumWorkspaceModel", "SkriptumCore", "SkriptumScheduling", "SkriptumAI"]),
        .testTarget(name: "SkriptumAITests", dependencies: ["SkriptumAI", "SkriptumCore"]),
        .testTarget(name: "SkriptumExportTests", dependencies: ["SkriptumExport"]),
        .testTarget(name: "SkriptumAuthTests", dependencies: ["SkriptumAuth"]),
        .testTarget(name: "SkriptumBlocksTests", dependencies: ["SkriptumBlocks"]),
        .testTarget(name: "SkriptumWritingQualityTests", dependencies: ["SkriptumWritingQuality", "SkriptumExport"], path: "Modules/SkriptumWritingQuality/Tests/SkriptumWritingQualityTests")
    ]
)
