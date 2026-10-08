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
        .library(name: "SkriptumBlocks", targets: ["SkriptumBlocks"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")
    ],
    targets: [
        .target(name: "SkriptumCore"),
        .target(name: "SkriptumAI", dependencies: ["SkriptumAuth"]),
        .target(name: "SkriptumAuth"),
        .target(name: "SkriptumBlocks", dependencies: ["SkriptumCore"]),
        .target(name: "SkriptumExport", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "SkriptumCoreTests", dependencies: ["SkriptumCore"]),
        .testTarget(name: "SkriptumAITests", dependencies: ["SkriptumAI", "SkriptumCore"]),
        .testTarget(name: "SkriptumExportTests", dependencies: ["SkriptumExport"]),
        .testTarget(name: "SkriptumAuthTests", dependencies: ["SkriptumAuth"]),
        .testTarget(name: "SkriptumBlocksTests", dependencies: ["SkriptumBlocks"])
    ]
)
