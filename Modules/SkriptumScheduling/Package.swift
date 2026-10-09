// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SkriptumScheduling", platforms: [.macOS("27.0"), .iOS("27.0")],
  products: [.library(name: "SkriptumScheduling", targets: ["SkriptumScheduling"])],
  targets: [
    .target(name: "SkriptumScheduling"),
    .testTarget(name: "SkriptumSchedulingTests", dependencies: ["SkriptumScheduling"]),
  ])
