# Changelog

All notable changes to this package are documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

Initial pre-release. The package is publishable to pub.dev once the
remaining roadmap items (DESIGN.md §9 steps 6–8) are complete; the
API surface is considered unstable until 1.0.0.

### Added

- `PlatinumapsMapView` widget that embeds the Platinumaps web map via
  a `PlatformView` (`UiKitView` on iOS, `AndroidView` on Android).
  Accepts `mapSlug`, `queryParams`, `locale`, `appStoreId`, `userId`,
  `secretKey`, `offsetBottom`, `coverImage`, `beacon`, `launchUrl`,
  and an `onOpenLink` callback. The iOS-only parameters are still
  accepted on Android for forward-compatibility but are silently
  ignored — see `README.md` for the parity table.
- `PlatinumapsBeaconOptions` for iBeacon configuration (uuid +
  optional minSample / maxHistory / memo).
- `PlatinumapsLocale` enum covering the eleven languages the
  Platinumaps web layer supports. Wire values match the iOS native
  SDK's `PMLocale` rawValue (e.g. `zh-cn`, `zh-tw`).
- `PlatinumapsOpenLinkCallback` typedef for the host-side
  open-in-app-browser callback. Mirrors the iOS native SDK's
  `PMMapViewDelegate.openLink(_:sharedCookie:)`.
- iOS native plugin: SwiftPM + CocoaPods both supported. The plugin
  glue compiles into a single target with the iOS SDK sources from
  `iOS/platinumaps-sdk/`, so consumers can choose either dependency
  manager.
- Android native plugin: source-bundled with the Kotlin sources from
  `Android/platinumaps-sdk/` via `sourceSets`, so the plugin
  compiles as a single library module with no pre-built AAR.
- `ActivityAware` plumbing on Android: the host Flutter app does not
  need to forward `onPause` / `onResume` / `onDestroy` /
  `onRequestPermissionsResult` / `onActivityResult` callbacks
  manually — the plugin does it automatically. This is a strict
  ergonomic improvement over the bare native Android SDK.
- iOS refactor: extracts a public `PMMapView` (UIView) out of the
  existing `PMMainViewController`. The original `PMMainViewController`
  stays as a thin forwarding wrapper so existing native-iOS
  integrators keep working unchanged.
- Localized permission-alert strings are now embedded directly in
  `PMLocalizedStrings.swift` rather than carried as a
  `Platinumaps.bundle` resource. Same translations as before, but
  the SDK is now self-contained for every distribution channel
  (manual integration, CocoaPods, SwiftPM, Flutter plugin).
- Shared `i18n/strings.yaml` source-of-truth at the repo root, with
  `scripts/generate-strings.py` regenerating both
  `PMLocalizedStrings.swift` and the Android `strings.xml` files.
- Example app at `Flutter/example/` demonstrating
  `PlatinumapsMapView` with `onOpenLink` plumbed through
  `url_launcher`, and a small `IgnorePointer` Flutter overlay
  stacked on top of the map to exercise the `§6 #3` gesture-
  passthrough composition case.
- Test suite covering the three DESIGN §7 layers:
  - Dart unit tests (`test/`) for the public API.
  - Android JUnit tests for the plugin's `buildMapOptions` parser.
  - iOS XCTest cases (in the example app's `RunnerTests` target)
    for the plugin's `applyCreationArguments(_:to:)` helper.
  - `integration_test/` smoke checks that the example app boots and
    mounts `PlatinumapsMapView` on real devices.
