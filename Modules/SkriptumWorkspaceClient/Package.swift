// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SkriptumWorkspaceClient", platforms: [.iOS("27.0"), .macOS("27.0")], products: [.library(name: "SkriptumWorkspaceClient", targets: ["SkriptumWorkspaceClient"])], targets: [.target(name: "SkriptumWorkspaceClient"), .testTarget(name: "SkriptumWorkspaceClientTests", dependencies: ["SkriptumWorkspaceClient"])])
