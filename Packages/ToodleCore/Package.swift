// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ToodleCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "ToodleCore", targets: ["ToodleCore"])], targets: [.target(name: "ToodleCore"), .testTarget(name: "ToodleCoreTests", dependencies: ["ToodleCore"], resources: [.process("Fixtures")])])
