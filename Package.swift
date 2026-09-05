// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Roger",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Roger", targets: ["Roger"]),
        .executable(name: "roger-doctor", targets: ["roger-doctor"]),
        .library(name: "RogerCore", targets: ["RogerCore"]),
        // Dynamic on purpose: nothing links against it. `/usr/bin/perl` loads
        // the built library at runtime — see Sources/MediaRemoteAdapter/README.
        .library(name: "MediaRemoteAdapter", type: .dynamic, targets: ["MediaRemoteAdapter"]),
    ],
    targets: [
        .target(
            name: "RogerCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Third-party, BSD 3-Clause. Kept as vendored sources rather than a
        // package dependency: see the README next to them.
        .target(
            name: "MediaRemoteAdapter",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
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
