// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SkriptumWritingQuality", platforms: [.iOS("27.0"), .macOS("27.0")], products: [.library(name: "SkriptumWritingQuality", targets: ["SkriptumWritingQuality"])], targets: [.target(name: "SkriptumWritingQuality"), .testTarget(name: "SkriptumWritingQualityTests", dependencies: ["SkriptumWritingQuality"])])
