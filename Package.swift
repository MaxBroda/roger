// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Roger",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Roger", targets: ["Roger"]),
        .executable(name: "roger-doctor", targets: ["roger-doctor"]),
        .library(name: "RogerCore", targets: ["RogerCore"]),
    ],
    targets: [
        .target(
            name: "RogerCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "roger-doctor",
            dependencies: ["RogerCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Roger",
            dependencies: ["RogerCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RogerCoreTests",
            dependencies: ["RogerCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
