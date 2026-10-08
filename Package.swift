// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Skriptum",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "SkriptumCore", targets: ["SkriptumCore"]),
        .library(name: "SkriptumAI", targets: ["SkriptumAI"]),
        .library(name: "SkriptumExport", targets: ["SkriptumExport"]),
        .library(name: "SkriptumAuth", targets: ["SkriptumAuth"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")
    ],
    targets: [
        .target(name: "SkriptumCore"),
        .target(name: "SkriptumAI", dependencies: ["SkriptumAuth"]),
        .target(name: "SkriptumAuth"),
        .target(name: "SkriptumExport", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "SkriptumCoreTests", dependencies: ["SkriptumCore"]),
        .testTarget(name: "SkriptumAITests", dependencies: ["SkriptumAI"]),
        .testTarget(name: "SkriptumExportTests", dependencies: ["SkriptumExport"]),
        .testTarget(name: "SkriptumAuthTests", dependencies: ["SkriptumAuth"])
    ]
)
