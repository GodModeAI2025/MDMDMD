// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Skriptum", platforms: [.iOS("27.0"), .macOS("27.0")], products: [.library(name: "SkriptumCore", targets: ["SkriptumCore"])], targets: [.target(name: "SkriptumCore"), .testTarget(name: "SkriptumCoreTests", dependencies: ["SkriptumCore"])])
