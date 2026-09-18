// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AiQokkaMenubar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AiQokkaMenubar", targets: ["AiQokkaMenubar"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AiQokkaMenubar",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "AiQokkaMenubarTests",
            dependencies: [
                "AiQokkaMenubar"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
