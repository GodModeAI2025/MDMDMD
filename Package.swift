// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Skriptum", platforms: [.iOS("27.0"), .macOS("27.0")], products: [.library(name: "SkriptumCore", targets: ["SkriptumCore"]), .library(name: "SkriptumAI", targets: ["SkriptumAI"])], targets: [.target(name: "SkriptumCore"), .target(name: "SkriptumAI"), .testTarget(name: "SkriptumCoreTests", dependencies: ["SkriptumCore"]), .testTarget(name: "SkriptumAITests", dependencies: ["SkriptumAI"])])
