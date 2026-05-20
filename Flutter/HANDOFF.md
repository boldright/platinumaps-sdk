# Handoff — Flutter SDK Implementation In Progress

This document captures the state of the Flutter SDK work so a new
session on a machine with the full toolchain (Flutter, Xcode, Android
SDK / JDK) can pick it up.

## Branch

```
claude/develop-flutter-sdk-AF35z
```

The branch is **ahead of `origin/main`** and contains both the design
document and the initial implementation. Always work on this branch
until merged.

## Recent commits (newest first)

```
f4558fa  Scaffold Flutter iOS plugin and make PMLocale public
f5698b6  Scaffold Flutter plugin: Dart API, Android plugin glue, project metadata
24e4148  Extract PMMapView (UIView) from PMMainViewController
36a0dbd  Address detailed review of Flutter SDK design
... (earlier commits: incremental DESIGN.md authoring)
```

## What's done

- **Design document.** `Flutter/DESIGN.md` is the source of truth.
  Read it before touching anything.
- **iOS native SDK refactor (Roadmap step 1a).** All bridge / WebView /
  sensor logic now lives on `iOS/platinumaps-sdk/Views/PMMapView.swift`
  (`public class PMMapView: UIView`, ~1611 lines). The existing
  `PMMainViewController` is preserved as a thin ~124-line forwarding
  wrapper so apps that follow `iOS/README.md` keep working unchanged.
  `PMMainViewControllerDelegate` is now a `typealias` of the new
  `PMMapViewDelegate`. `PMLocale` was promoted to `public` so it can
  cross module boundaries.
- **Flutter package scaffold.** `Flutter/pubspec.yaml`,
  `analysis_options.yaml`, `.gitignore`, `CHANGELOG.md`, `LICENSE`,
  `README.md`.
- **Dart API (Roadmap step 3).** `PlatinumapsMapView` (StatefulWidget
  hosting `AndroidView` / `UiKitView`), `PlatinumapsBeaconOptions`,
  `PlatinumapsLocale` (11 entries matching iOS `PMLocale`). Exports
  via `lib/platinumaps_flutter_sdk.dart`.
- **Android plugin glue (Roadmap step 1b).** `PlatinumapsFlutterPlugin`
  (`FlutterPlugin` + `ActivityAware`, auto-forwards permission and
  activity results), `PlatinumapsPlatformViewFactory`,
  `PlatinumapsPlatformView` wrapping `PmWebView`. The vendored AAR
  at `Flutter/android/libs/platinumaps-sdk.aar` is a copy of
  `Android/platinumaps-sdk-release.aar` and **may be stale** —
  rebuild before any meaningful Android test (see commands below).
- **iOS plugin glue (Roadmap step 2).** Mirror of the Android side.
  The podspec vendors the iOS SDK Swift sources from
  `../../iOS/platinumaps-sdk/` via a glob; this works only for
  in-repo / Git-path consumption and **breaks for `dart pub
  publish`** (tracked as DESIGN.md §8 #4).
- **Activity lifecycle forwarding (Roadmap step 4).** Android side
  done via `ActivityAware`. iOS needs none — `PMMapView` self-
  installs `UIApplication` foreground / background observers.

## What's NOT verified

Nothing in this branch has been compiled or executed because the
session that produced it had no toolchain. The first job in the new
session is to **prove the existing code compiles and the example
boots**.

Specifically:

- `swift build` against the refactored iOS SDK has never run.
- `flutter pub get` / `flutter analyze` against `Flutter/` has never
  run.
- `./gradlew :platinumaps-sdk:assembleRelease` against the existing
  Android sample has run *before* the iOS refactor, but not after
  (no Android sources changed, so it should still pass).
- The Flutter plugin has never been instantiated against either
  native side.
- The existing iOS sample integration described in `iOS/README.md`
  has never been re-run against the refactored SDK. This is the
  regression gate for step 1a.

## First commands to run on the local machine

```bash
# 1. Check out the branch.
git fetch origin claude/develop-flutter-sdk-AF35z
git checkout claude/develop-flutter-sdk-AF35z

# 2. Confirm the iOS refactor compiles.
swift build              # from the repo root

# 3. Confirm the Dart side analyzes cleanly.
cd Flutter
flutter pub get
flutter analyze
cd ..

# 4. Refresh the vendored AAR. The Android source has not changed
#    since the AAR was first committed, but redo this any time
#    Android/platinumaps-sdk source changes.
cd Android/sample
./gradlew :platinumaps-sdk:assembleRelease
cp ../platinumaps-sdk/build/outputs/aar/platinumaps-sdk-release.aar \
   ../../Flutter/android/libs/platinumaps-sdk.aar
cd ../..

# 5. Run the existing iOS sample (manual smoke test described in
#    iOS/README.md) to confirm the refactor did not regress the
#    public PMMainViewController contract.

# 6. Run the existing Android sample (Android/sample/) to confirm
#    Android side is unaffected.
```

## What to do next (Roadmap step 5 onward)

1. **Create `Flutter/example/`.** `flutter create --template=app
   --org jp.co.boldright --platforms ios,android example` from
   `Flutter/`. Edit `example/lib/main.dart` to render a single
   `PlatinumapsMapView(mapSlug: 'demo')`. Add a `path: ../`
   dependency on the parent plugin.
2. **Wire the rest of step 3.** The `coverImage` (Dart `ImageProvider`
   → native `UIImage` on iOS, no Android equivalent yet) is the only
   creation parameter currently dropped on the floor. Decide whether
   v0.1 ships without it (mark iOS-only in the Dart API and don't
   pretend to send it across the channel at all) or wires it through
   for iOS.
3. **PlatformView composition checks (Roadmap step 5).** Confirm in
   the example app that
   - The native cover image draws above the WebView until `web.ready`
     and below any Flutter `Stack` overlay you place on top.
   - System modals (permission alerts, file chooser intent) sit
     above Flutter overlays.
   - Gesture conflicts behave per the recommended pattern documented
     in `Flutter/README.md`.
4. **Test suite (Roadmap step 6).** Dart unit tests for option
   serialization and the locale wire format. `integration_test`
   driven from the example app.
5. **Static analysis (Roadmap step 7).** Zero `flutter analyze`
   warnings, `pana` at target tiers per DESIGN.md §7.
6. **Resolve `Flutter/DESIGN.md` §8 open questions** before any
   pub.dev publish. The native-SDK packaging question (#4) blocks
   publish; the rest are cleanups.

## Known fragile spots to validate first

- **`PMMapView` first-attach lifecycle.** `didMoveToWindow` runs the
  one-time setup behind an `isFirstAttach` latch. Verify the URL
  builds and the WebView loads on first attach, and that detach /
  reattach (e.g., the view is removed and re-added to the hierarchy)
  does **not** re-run the setup.
- **`present(_:animated:)` routing.** The wrapper
  `PMMainViewController` no longer overrides `present`; the topmost-
  presented walk now lives in a `UIView` extension
  (`presentationViewController`) inside `PMMapView.swift`. Trigger a
  permission alert while the host already has another modal up — the
  SDK alert should land on top of that modal, not produce the
  "Attempt to present X on Y while Z is presented" warning.
- **`PMMapView` resource bundle access.** `PMMapView.bundle` still
  uses `Bundle.main.path(forResource: "Platinumaps", ofType:
  "bundle")`. The Flutter plugin's podspec uses `s.resources` to
  copy `Platinumaps.bundle` into the main app bundle so this lookup
  succeeds. Verify that permission-denied alerts in the example app
  carry localized strings.
- **PlatformView gesture passthrough.** Default
  `AndroidView` / `UiKitView` behaviour is to forward all gestures
  to the native view. A Flutter `GestureDetector` placed in a
  `Stack` above the map will not receive taps unless explicitly
  configured.

## Files to read first (in order)

1. `Flutter/DESIGN.md` — full design, including §8 open questions
   and §9 roadmap.
2. `CLAUDE.md` — repository conventions, bridge protocol,
   threading model. Read the sections on Android lifecycle and
   iOS lifecycle; the Flutter plugin satisfies the Android
   contract automatically but the contract itself still applies.
3. `iOS/platinumaps-sdk/Views/PMMapView.swift` — the public iOS
   surface the Flutter plugin (and any native iOS host) consumes.
4. `Flutter/lib/src/platinumaps_map_view.dart` — Dart API and the
   creation-arguments wire format.
5. This file's "What to do next" list.
