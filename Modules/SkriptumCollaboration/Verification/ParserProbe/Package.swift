// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "ParserProbe", platforms: [.macOS("27.0")], dependencies: [.package(url: "https://github.com/automerge/automerge-swift.git", exact: "0.7.2")], targets: [.executableTarget(name: "ParserProbe", dependencies: [.product(name: "Automerge", package: "automerge-swift")])])
