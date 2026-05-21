# Flutter SDK — Design

Contributor-facing reference for *why* the Platinumaps Flutter SDK is
shaped the way it is. End-user integration instructions live in
[`platinumaps_flutter_sdk/README.md`](platinumaps_flutter_sdk/README.md);
this document complements that with the rationale a maintainer needs
to make consistent changes.

## 1. Goal & non-goals

The Flutter SDK lets a Flutter host application embed the Platinumaps
web layer with the same fidelity the existing iOS and Android native
SDKs offer — geolocation, heading (Android), iBeacon ranging, in-app
browser, store review, file chooser, and the `command://` bridge —
while remaining publishable on pub.dev and composable with the host's
own Flutter widgets.

Out of scope for v1:

- **Customer-facing extension hooks** (custom commands, swappable
  permission UI, alternate WebView engines).
- **Federated plugin layout.** v1 targets iOS and Android only, no
  third-party implementation is expected. A future migration remains
  possible if web or desktop become requirements.
- **Web / desktop targets.** Mobile only.

## 2. Approach: wrap the existing native SDKs

The Flutter SDK delegates all WebView ownership, `command://` parsing,
and OS-level integrations to the existing `PmWebView` (Android) and
`PMMapView` (iOS). The Flutter layer is a thin PlatformView host plus
a Dart configuration / event surface.

### Why not reimplement in Dart

The native SDKs are not thin protocol decoders (`PmWebView` is ~2,000
lines; the iOS counterpart similar). The complexity lives in parts
that took multiple iterations to get right:

- Bridge security — JSON-encoding every argument before
  `evaluateJavascript` to defeat injection via URL-controlled
  `requestId`.
- Scheme allowlisting for `browse.app` / `browse.inapp` / `map.navigate`.
- Initial-load retry with exponential backoff.
- Concurrency fixes (BLE callback main-thread bounce, NaN/Infinity
  filtering before JSON serialization, magnetometer cleanup, beacon
  UUID validation, …).
- The growing command catalogue.

A Dart re-implementation would either copy these line-by-line and risk
re-introducing solved problems, or drift from the native SDKs as the
bridge protocol evolves. Wrapping the existing implementation inherits
every past and future fix for free.

### Alternatives considered

| | Pure Dart | Hybrid (Dart bridge + native sensors) | **Wrap native SDKs (chosen)** |
|---|---|---|---|
| WebView | `flutter_inappwebview` | `flutter_inappwebview` | Native `PmWebView` / `PMMapView` |
| `command://` parsing | Dart | Dart | Native |
| Bridge security / retry | Dart re-implementation | Dart re-implementation | Inherited |
| Sensors / iBeacon | pub packages + native bridge | Native via MethodChannel | Native |
| Effort to ship v1 | High | High | Low |
| Effort to follow upstream | Per-command port | Per-command port | Bump native SDK version |
| Customer extension surface | Large | Large | Limited to what the native SDKs expose |

Customer extensibility was the only reason to consider 1 or 2. With it
demoted to non-goal, wrap is the cheapest path and aligns with the
existing native investment.

## 3. Architecture

```
+----------------------------------------------------+
| Flutter host app                                   |
|   PlatinumapsMapView(...)   ←  Dart Widget API     |
+------------------|---------------------------------+
                   |
+------------------v---------------------------------+
| platinumaps_flutter_sdk (this package)             |
|   Dart: PlatinumapsMapView, options, callbacks     |
|   ├── AndroidView      (Android, hybrid comp.)     |
|   ├── UiKitView        (iOS)                       |
|   └── MethodChannel: jp.co.boldright.platinumaps   |
|        (native → Dart: onOpenLink callback)        |
+------------------|---------------------------------+
                   |
+------------------v---------------------------------+
| Plugin native layer                                |
|   Android: PlatinumapsPlatformViewFactory          |
|             └─ wraps PmWebView                     |
|   iOS:    PlatinumapsPlatformViewFactory           |
|             └─ wraps PMMapView                     |
+------------------|---------------------------------+
                   |
+------------------v---------------------------------+
| Existing native SDKs (this repo)                   |
|   Android/platinumaps-sdk   (Kotlin)               |
|   iOS/platinumaps-sdk       (Swift)                |
+----------------------------------------------------+
```

The plugin directory has to be named `platinumaps_flutter_sdk` to
match `pubspec.yaml`'s `name:`; Flutter's plugin-injection step uses
that directory basename as the SwiftPM package identity, and a
mismatch causes Xcode to reject the package graph.

### iOS — `PMMapView` extraction

Flutter's `UiKitView` requires a `UIView`, but the original iOS SDK's
entry point (`PMMainViewController`) is a `UIViewController`. The iOS
SDK was refactored so all bridge / WebView / sensor logic lives on
`PMMapView` (a `UIView`), with `PMMainViewController` kept as a thin
forwarding wrapper for existing native-iOS integrators. The current
shape is the source of truth — see `iOS/platinumaps-sdk/Views/PMMapView.swift`.

One subtlety: `UIView` cannot present view controllers, so calls like
`UIAlertController` / `SFSafariViewController` need a `UIViewController`
to host them. `PMMapView.presentationViewController` walks the
responder chain (`self.next` until a `UIViewController` is found) and
then descends `presentedViewController` to the top of any modal stack
already in flight. The lookup lands on `PMMainViewController` in the
native path and on `FlutterViewController` in the Flutter path —
same observable presentation semantics in both.

### Threading

- **iOS** — `PMMapView` is a `UIView`, implicitly `@MainActor` under
  UIKit's Swift 6 annotations. All bridge callbacks
  (`evaluateJavaScript`, `WKNavigationDelegate`, location / beacon
  delegates) are main-thread. The one explicit `Task.sleep` (120 ms
  heading-catchup after the first location sample) marshals back to
  the main actor via `[weak self]`. `deinit` wraps sensor cleanup in
  `MainActor.assumeIsolated { … }` because `UIView` deallocation runs
  on the main thread.
- **Android** — `WebView` and all mutable state is touched only from
  the main looper. BLE `ScanCallback` arrives on a binder thread, so
  `leScanCallback` re-posts every result through `mainHandler` before
  mutating `beaconBuffer`.

## 4. Distribution

In-repo development uses relative paths from
`Flutter/platinumaps_flutter_sdk/` to the existing
`Android/platinumaps-sdk/` Kotlin sources and `iOS/platinumaps-sdk/`
Swift sources. That arrangement does **not** survive `dart pub
publish`: only the contents of `Flutter/platinumaps_flutter_sdk/` are
uploaded.

The choice was between bundling sources at publish time, bundling
prebuilt artifacts (AAR / xcframework), and depending on external
artifact repositories (Maven Central / a separate CocoaPod).
**Bundling sources won** — flatdir AAR consumption did not survive
through Flutter host projects, and external repositories tie release
cadences across artifacts that today live in one repo.

In-repo wiring:

- **Android** — `android/build.gradle` adds
  `../../../Android/platinumaps-sdk/src/main/java` to the plugin's
  `main.java.srcDirs` and the matching `res` directory to
  `main.res.srcDirs`. The Android `namespace` is set to
  `jp.co.boldright.platinumaps.sdk` so the generated `R` /
  `BuildConfig` classes appear where the vendored sources expect them
  (the Flutter plugin glue itself lives in
  `jp.co.boldright.platinumaps.flutter`). `buildFeatures.buildConfig`
  is `true` because the SDK reads `BuildConfig.DEBUG`.
- **iOS** — `Sources/PlatinumapsSDK/` is a *byte-identical copy* of
  `iOS/platinumaps-sdk/` (same pattern as the Android sample
  mirror — see CLAUDE.md). Both the SwiftPM build
  (`platinumaps_flutter_sdk/Package.swift`) and the CocoaPods build
  (`platinumaps_flutter_sdk.podspec`) read from this in-package
  copy. A symlink would have been preferable but CocoaPods on the
  Flutter 3.32-3.43 path neither follows symlinks nor resolves the
  `../../../iOS/platinumaps-sdk` relative glob from the
  `ios/.symlinks/plugins/<plugin>/` install location, so the
  generated `Pods.xcodeproj` ended up without the SDK sources. The
  mirror sidesteps both problems. CI enforces
  `diff -r iOS/platinumaps-sdk Flutter/.../Sources/PlatinumapsSDK`
  in the `mirror-sync` job.

Publish workflow — `scripts/prepublish.py`:

- Copies the Kotlin sources into the plugin's `android/src/main/kotlin/`.
- Drops the `srcDirs` overrides in `build.gradle.kts` and the
  `Sources/PlatinumapsSDK` glob in the podspec into a single
  recursive `Sources/**/*.swift` after publishing.
- The CI `publish-dry-run` job exercises the snapshot end-to-end on
  every push.

## 5. PlatformView composition decisions

PlatformView lets the Flutter host stack widgets on top of the native
WebView. Three composition cases were considered:

1. **Cover image vs Flutter splash.** The iOS native SDK draws a
   cover image on top of the WebView until `web.ready`. The Flutter
   SDK deliberately does *not* surface that knob — drive the splash
   from the Flutter host instead (compose a widget above the map in a
   `Stack`, or defer mounting until the host splash finishes). The
   host has access to richer Flutter primitives than a single
   `ImageProvider` would provide, and the `web.ready` signal that the
   native cover image relies on is not surfaced to Dart.
2. **Native modals.** `UIAlertController` (iOS) and the file-chooser
   `Intent` (Android) present above everything, including Flutter
   overlays. This is the desired behaviour for permission prompts and
   needs no special handling.
3. **Gesture conflicts.** Flutter widgets placed in a `Stack` above
   the PlatformView must not steal touches intended for the map. Use
   `IgnorePointer` on full-bleed decorations and explicit gesture
   detectors only on UI elements that need them. The example app
   demonstrates the pattern.

## 6. Testing & CI

| Layer | Scope | Tooling |
|-------|-------|---------|
| Dart unit tests (`test/`) | Pure-Dart logic: options serialization, public API contracts | `flutter test` |
| Native plugin unit tests | Thin plugin glue only (factory creation arguments, MethodChannel routing). The bundled iOS/Android SDK modules retain their own test posture independently. | Android JUnit, iOS XCTest |
| Integration tests (`integration_test/`) | End-to-end behaviour from the example app | `flutter test integration_test` |
| Manual smoke checks | Hardware-only flows CI cannot exercise: GPS fix on a moving device, iBeacon ranging, camera-backed file chooser | Physical iOS / Android devices |

Test coverage is reported per PR but no numerical gate is enforced —
the integration tests are the primary safety net.

CI (`.github/workflows/flutter-sdk-ci.yml`) enforces, on every push:

- `dart format`, `flutter analyze`, and `flutter test` across Flutter
  stable & beta on Linux.
- The Android plugin's JUnit suite.
- The iOS plugin's XCTest cases on macOS.
- `pana` (category-level, not absolute score).
- `dart pub publish --dry-run` against `scripts/prepublish.py`'s
  snapshot.
- An i18n drift check that re-runs `scripts/generate-strings.py` and
  fails if the regenerated files differ from what's committed.

## 7. Decisions

Settled choices recorded so future contributors do not need to
re-derive the rationale.

- **AGP 8 / AGP 9 dual support.** The plugin's Android build script
  uses Kotlin DSL with the `plugins { id("com.android.library") }`
  block so it parses under AGP 8 (Flutter 3.32-3.43) and AGP 9
  (Flutter 3.44+). The `kotlin-android` Gradle plugin is applied
  via a runtime `if (agpMajor < 9)` guard — AGP 9+ bundles Kotlin
  built-in, and applying KGP there triggers a deprecation warning
  in the host project's build output. Both toolchains are verified
  by building the example app with each AGP version pinned in
  `Flutter/example/android/settings.gradle.kts`.

- **Beacon configuration timing.** `PlatinumapsBeaconOptions` is
  passed through `creationParams` only; mutating Dart state after
  the widget is built has no effect until the widget rebuilds with a
  fresh key. Mirrors the native SDKs, which take beacon options at
  `openPlatinumaps` time and treat them as immutable.
- **CocoaPods vs SwiftPM.** Ship both, sharing the same Swift
  sources, so the plugin works regardless of which iOS dependency
  manager the host project uses.
- **Coverage of native packaging for pub.dev.** Bundle sources at
  publish time (see §4) — chosen over prebuilt AAR / xcframework or
  separate Maven / CocoaPods publishing pipelines.
- **`coverImage` parity.** The Flutter SDK does not expose
  `coverImage`. The Flutter host is better positioned to drive a
  splash (see §5 #1). If concrete demand emerges, add it as a named
  constructor parameter — backwards compatible.
- **Naming alignment.** The native-SDK names stay as-is (iOS
  `mapSlug` / Android `mapPath`; iOS `mapQuery` / Android
  `queryParams`); the plugin glue translates. Renaming public
  surfaces in the native SDKs would break every existing native-iOS
  / native-Android integrator for marginal Dart-side benefit.
- **`PlatinumapsLocale` wire format.** The Dart enum's `code`
  strings match the iOS `PMLocale` raw values one-for-one (eleven
  entries: `ja`, `en`, `zh-cn`, `zh-tw`, `ko`, `fr`, `es`, `vi`,
  `id`, `my`, `th`); the Android plugin glue folds the same string
  into the `culture` query parameter.
- **Permission acquisition responsibility.** Inherit the native
  SDKs' behaviour unchanged. The Flutter plugin does no permission
  work itself; hosts declare the relevant `Info.plist` keys and
  `AndroidManifest.xml` permissions, with no `permission_handler`
  dependency required.
- **`isWebViewInspectable` exposure.** v1 omits it from the Dart
  API; debug-only behaviour (Android already gates on
  `BuildConfig.DEBUG`) is sufficient. Reopen if customers ask for
  release-build debugging.

## 8. Open / future

- **First pub.dev publish.** The package is publishable
  (`dart pub publish --dry-run` clean) but blocked on (a) manual
  sensor-dependent smoke checks (GPS / iBeacon / camera) — expected
  to ride the existing TestFlight + Play Console internal-track
  workflow — and (b) an independent end-to-end walkthrough of
  `README.md` by someone who did not write the SDK.
- **Imperative controller scope.** `PlatinumapsMapController.pushLaunchUrl(Uri)`
  is in place; runtime locale / beacon / query-param updates remain
  rebuild-only. Add them when concrete demand is observed.
