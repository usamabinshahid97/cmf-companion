// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CMFCompanion",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CMFCompanion", targets: ["CMFCompanion"])],
    targets: [
        .target(name: "BudsCore"),
        .executableTarget(name: "CMFCompanion", dependencies: ["BudsCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)],
                          linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("CoreBluetooth")]),
        .testTarget(name: "BudsCoreTests", dependencies: ["BudsCore"])
    ]
)
