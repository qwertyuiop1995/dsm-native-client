// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DsmShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "DsmCore", targets: ["DsmCore"]),
        .library(name: "DsmNetwork", targets: ["DsmNetwork"]),
        .executable(name: "LanStash", targets: ["DsmMacExecutable"])
    ],
    targets: [
        .target(
            name: "DsmCore",
            path: "Packages/DsmCore/Sources"
        ),
        .target(
            name: "DsmNetwork",
            dependencies: ["DsmCore"],
            path: "Packages/DsmNetwork/Sources",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "DsmMacExecutable",
            dependencies: ["DsmCore", "DsmNetwork"],
            path: "Apps/DsmMac/Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "DsmCoreTests",
            dependencies: ["DsmCore"],
            path: "Packages/DsmCore/Tests"
        ),
        .testTarget(
            name: "DsmNetworkTests",
            dependencies: ["DsmCore", "DsmNetwork"],
            path: "Packages/DsmNetwork/Tests"
        ),
        .testTarget(
            name: "DsmMacTests",
            dependencies: ["DsmCore", "DsmMacExecutable"],
            path: "Apps/DsmMac/Tests"
        )
    ]
)
