// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EmmaPortrait", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "EmmaPortrait", targets: ["EmmaPortrait"])], targets: [.target(name: "EmmaPortrait", resources: [.process("Resources")])])
