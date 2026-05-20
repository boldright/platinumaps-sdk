// swift-tools-version: 5.9
//
// Swift Package manifest for the Platinumaps Flutter plugin.
//
// Flutter 3.x began requiring Swift Package Manager support for iOS
// plugins. This manifest exists so `flutter analyze` no longer warns
// about the missing SwiftPM adoption; the CocoaPods podspec next to it
// continues to work for hosts that have not opted in to SwiftPM yet.
//
// Both managers read the same Swift sources:
//
// - The plugin's own glue lives under
//   `Sources/platinumaps_flutter_sdk/`.
// - The native iOS SDK sources are pulled in through a second target
//   (`PlatinumapsSDK`) that points back at `iOS/platinumaps-sdk/`.
//   The plugin glue declares `dependencies: ["PlatinumapsSDK"]` and
//   adds `import PlatinumapsSDK` only when compiled by SwiftPM (the
//   CocoaPods build is single-module and so does not need it).
//
// At publish time the `iOS/platinumaps-sdk/` sources are copied into
// `Sources/PlatinumapsSDK/` so the manifest no longer needs the `path`
// override; see `Flutter/DESIGN.md` §5.

import PackageDescription

let package = Package(
    name: "platinumaps_flutter_sdk",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        .library(
            name: "platinumaps-flutter-sdk",
            targets: ["platinumaps_flutter_sdk"]
        ),
    ],
    dependencies: [
        // FlutterFramework is the SwiftPM-flavoured shim for `import
        // Flutter`. Flutter's own SwiftPM-aware build supplies the
        // actual package at `../FlutterFramework` relative to this
        // manifest; that path is conventionally provided by the
        // Flutter tool when it integrates plugin packages into the
        // host app's workspace.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "PlatinumapsSDK",
            path: "../../../iOS/platinumaps-sdk",
            resources: [
                .process("Platinumaps.bundle"),
            ]
        ),
        .target(
            name: "platinumaps_flutter_sdk",
            dependencies: [
                "PlatinumapsSDK",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
