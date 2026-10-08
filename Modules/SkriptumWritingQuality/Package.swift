// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SkriptumWritingQuality", platforms: [.iOS("27.0"), .macOS("27.0")], products: [.library(name: "SkriptumWritingQuality", targets: ["SkriptumWritingQuality"])], dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")], targets: [.target(name: "SkriptumWritingQuality", dependencies: [.product(name: "Markdown", package: "swift-markdown")]), .testTarget(name: "SkriptumWritingQualityTests", dependencies: ["SkriptumWritingQuality"])])
