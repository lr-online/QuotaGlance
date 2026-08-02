// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaGlance",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "QuotaGlanceCore", targets: ["QuotaGlanceCore"])
    ],
    targets: [
        .target(
            name: "QuotaGlanceCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "QuotaGlanceCoreTests",
            dependencies: ["QuotaGlanceCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
