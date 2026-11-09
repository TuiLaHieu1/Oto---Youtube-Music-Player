// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OtoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OtoCore",
            targets: ["OtoCore"]
        )
    ],
    targets: [
        .target(
            name: "OtoCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OtoCoreTests",
            dependencies: ["OtoCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
