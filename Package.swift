// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlatinumapsSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PlatinumapsSDK", targets: ["PlatinumapsSDK"]),
    ],
    targets: [
        .target(
            name: "PlatinumapsSDK",
            path: "iOS/platinumaps-sdk",
            resources: [.process("Platinumaps.bundle")]
        ),
    ]
)
