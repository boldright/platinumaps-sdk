// swift-tools-version: 5.9
//
// Swift Package manifest for the Platinumaps Flutter plugin.
//
// In-repo layout:
//
//   Sources/platinumaps_flutter_sdk/  — plugin glue (FlutterPlugin, factory,
//                                        per-instance PlatformView).
//   Sources/PlatinumapsSDK/           — byte-identical mirror of
//                                        `iOS/platinumaps-sdk/`. CocoaPods cannot
//                                        follow a symlink into the canonical
//                                        tree (see the podspec for details), so
//                                        the Flutter plugin keeps its own copy
//                                        here. The CI `mirror-sync` job enforces
//                                        the byte-identity.
//
// Plugin glue and SDK sources compile into a single
// `platinumaps_flutter_sdk` target. Two reasons:
//
//  1. Flutter's plugin injection step marks the plugin package as a
//     local override of an ephemeral copy in the host workspace. With
//     a multi-target package the override comparison sees an identity
//     mismatch ("unable to override package … because its identity
//     'flutter' doesn't match") and refuses to resolve.
//  2. The CocoaPods build is also a single module, so a single SwiftPM
//     target keeps the two build paths aligned.
//
// The SDK no longer ships any resource bundles (localized strings are
// embedded in `PMLocalizedStrings.swift`), so this manifest does not
// need `defaultLocalization` or a `resources:` entry.

import PackageDescription

let package = Package(
    name: "platinumaps_flutter_sdk",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        // Flutter's SwiftPM plugin convention requires plugin names
        // that contain an underscore (`platinumaps_flutter_sdk`) to
        // expose a hyphen-separated library product. The
        // `FlutterGeneratedPluginSwiftPackage` that Flutter generates
        // at build time references this library by its hyphenated
        // name, so changing it here breaks the host app's package
        // resolution (`product 'platinumaps-flutter-sdk' ... not
        // found in package 'platinumaps_flutter_sdk'`).
        .library(
            name: "platinumaps-flutter-sdk",
            targets: ["platinumaps_flutter_sdk"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "platinumaps_flutter_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources",
            sources: [
                "platinumaps_flutter_sdk",
                "PlatinumapsSDK",
            ]
        ),
    ]
)
