// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GSKit",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "GSKit", targets: ["GSKit"]),
    ],
    targets: [
        .target(
            name: "GSKit",
            dependencies: [],
            path: "Sources/GSKit",
            resources: [
                .process("Shaders/GaussianSurface.usda"),
            ]
        ),
    ]
)
