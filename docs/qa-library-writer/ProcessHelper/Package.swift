// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LibraryProcessProof", platforms: [.macOS("27.0")], dependencies: [
    .package(path: "../../..")
], targets: [.executableTarget(name: "LibraryProcessProof", dependencies: [
    .product(name: "SkriptumCore", package: "Skriptum")
])])
