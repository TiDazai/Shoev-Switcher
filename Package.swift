// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ShoevSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ShoevSwitcher", targets: ["ShoevSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "ShoevSwitcher",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ShoevSwitcherTests",
            dependencies: ["ShoevSwitcher"]
        )
    ]
)
