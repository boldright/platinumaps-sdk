# Flutter SDK — Design

Status: **Draft for review**. No implementation has begun. This document is
the single source of truth for the planned Flutter SDK and is intended to
be reviewed before any code lands.

## 1. Goal

Provide a Flutter package that lets a Flutter host application embed the
Platinumaps web layer with the same fidelity the existing iOS and Android
native SDKs offer — geolocation, heading (Android), iBeacon ranging,
in-app browser, store review, file chooser, and the `command://` bridge —
while remaining publishable on pub.dev and composable with the host's own
Flutter widgets.

### Non-goals (for the first release)

- **Customer-facing extension hooks** (custom commands, swappable
  permission UI, alternate WebView engines). Treated as future work; not
  designed for in v1.
- **Federated plugin layout.** A federated Flutter plugin splits into
  four packages — an app-facing facade, a `platform_interface`, and
  one implementation package per platform (e.g. `_android`, `_ios`,
  `_web`). The pattern is the right answer when third parties are
  expected to contribute new platform implementations, or when each
  platform needs an independent release cadence (see `url_launcher`,
  `path_provider`). Neither applies here: the SDK targets iOS and
  Android only, no third-party implementation is expected, and the
  existing native SDKs in this repo are referenced by relative path,
  not as separately-published artifacts. v1 ships as a single
  non-federated package; a future migration to a federated layout
  remains possible if web or desktop targets become requirements.
- **Web / desktop targets.** Mobile only.

## 2. Approach: wrap the existing native SDKs

The Flutter SDK delegates all WebView ownership, `command://` parsing, and
OS-level integrations to the existing `PmWebView` (Android) and the
refactored `PMMapView` (iOS, see §4). The Flutter layer is a thin
PlatformView host plus a Dart configuration / event surface.

### Why not reimplement in Dart

The native SDKs are not a thin protocol decoder. As of this writing:

- Android `PmWebView`: 1,989 lines.
- iOS `PMMainViewController`: 1,585 lines.

The complexity lives in the parts that took multiple iterations to get
right:

- Bridge security — JSON-encoding every argument before
  `evaluateJavascript` to defeat injection via URL-controlled
  `requestId`.
- Scheme allowlisting for `browse.app` / `browse.inapp` / `map.navigate`.
- Initial-load retry with exponential backoff (~170 lines per platform).
- Concurrency fixes (BLE callback main-thread bounce, NaN/Infinity
  filtering before JSON serialization, magnetometer cleanup on destroy,
  beacon UUID validation up front, …).
- The growing command catalogue (recent additions: `stamprally.qrcode`,
  `search.focus`).

A Dart re-implementation would either copy these line-by-line and risk
re-introducing solved problems, or drift from the native SDKs as the
bridge protocol evolves. Wrapping the existing implementation inherits
every past and future fix for free.

### Alternatives considered

| | Approach 1: Pure Dart | Approach 2: Hybrid | **Approach 3: Wrap native SDKs (chosen)** |
|---|---|---|---|
| WebView | `flutter_inappwebview` | `flutter_inappwebview` | Native `PmWebView` / `PMMapView` via PlatformView |
| `command://` parsing | Dart | Dart | Native |
| Bridge security / retry | Dart re-implementation | Dart re-implementation | Inherited |
| Location / compass / file / permissions | pub.dev packages | Native code extracted via MethodChannel | Native |
| iBeacon | Native code extracted via MethodChannel | Native code extracted via MethodChannel | Native |
| Effort to ship v1 | High | High | Low |
| Effort to follow upstream | Per-command port | Per-command port | Bump native SDK version |
| Customer extension surface | Large (Dart hooks) | Large (Dart hooks) | Limited to whatever the native SDKs expose |

Customer extensibility was the main reason to consider 1 / 2. With it
demoted to non-goal (§1), the wrap approach is the cheapest path and the
one most aligned with the existing investment.

## 3. Architecture

```
+----------------------------------------------------+
| Flutter host app                                   |
|                                                    |
|   PlatinumapsMapView(...)   ←  Dart Widget API     |
+------------------|---------------------------------+
                   |
+------------------v---------------------------------+
| platinumaps_flutter_sdk (this package)             |
|                                                    |
|   Dart: PlatinumapsMapView, options, callbacks     |
|   ├── AndroidView       (Android, hybrid comp.)    |
|   ├── UiKitView         (iOS)                      |
|   │     ↑ creation arguments carry the full        |
|   │       PlatinumapsMapView configuration         |
|   └── MethodChannel: jp.co.boldright.platinumaps   |
|         (native → Dart: onOpenLink callback)       |
+------------------|---------------------------------+
                   |
+------------------v---------------------------------+
| Plugin native layer                                |
|                                                    |
|   Android: PlatinumapsPlatformViewFactory          |
|             └─ wraps existing PmWebView            |
|   iOS:    PlatinumapsPlatformViewFactory           |
|             └─ wraps refactored PMMapView          |
+------------------|---------------------------------+
                   |
+------------------v---------------------------------+
| Existing native SDKs (this repo)                   |
|                                                    |
|   Android/platinumaps-sdk   (Kotlin, unchanged)    |
|   iOS/platinumaps-sdk       (Swift, refactored §4) |
+----------------------------------------------------+
```

### Repository layout (after these changes)

```
.
├── CLAUDE.md
├── README.md
├── Package.swift                ← existing iOS Swift Package
├── iOS/                         ← existing iOS SDK (refactored)
├── Android/                     ← existing Android SDK (unchanged)
└── Flutter/                     ← new
    ├── README.md                ← integration guide for Flutter hosts
    ├── DESIGN.md                ← this document
    ├── pubspec.yaml
    ├── lib/                     ← Dart implementation
    ├── android/                 ← Gradle project; depends on ../Android/platinumaps-sdk via :include or local AAR
    ├── ios/                     ← podspec / Swift Package; depends on ../Package.swift via path
    └── example/                 ← runnable sample app
```

The two existing Android sample-mirror directories
(`Android/platinumaps-sdk` and `Android/sample/platinumaps-sdk`,
required by CLAUDE.md to stay byte-identical) are unaffected. The
Flutter plugin's `android/` references the canonical
`Android/platinumaps-sdk` only.

## 4. iOS refactor: `PMMainViewController` → `PMMapView`

Flutter's `UiKitView` requires a `UIView`. The current iOS SDK's entry
point, `PMMainViewController`, is a `UIViewController`. We refactor the
SDK so the entirety of the bridge / WebView / sensor logic lives on a
`UIView` subclass that PlatformView can host directly.

### Migration shape

```
Before:
  PMMainViewController (UIViewController)
    └─ all logic (~1,585 lines)

After:
  PMMapView (UIView)                  ← new, holds all logic
    └─ embedded directly by Flutter via UiKitView

  PMMainViewController (UIViewController)
    └─ thin wrapper (~100 lines) that:
        - owns a PMMapView,
        - forwards every existing public property / delegate to it,
        - so existing native-iOS integrators keep working unchanged.
```

### Lifecycle mapping

| `UIViewController` | `UIView` replacement |
|--------------------|----------------------|
| `viewDidLoad` | `init(frame:)` + lazy setup on first `didMoveToWindow` |
| `viewDidAppear` | `didMoveToWindow` with an `isFirstAttach` latch |
| `view.safeAreaInsets` | `self.safeAreaInsets` |
| `view.addSubview` | `self.addSubview` |
| `view.bringSubviewToFront` | `self.bringSubviewToFront` |
| `UIApplication.willEnter/didEnterBackground` observers | unchanged |
| `CLLocationManagerDelegate` | unchanged |

### The `present(_:animated:)` problem

`PMMainViewController` calls `present` in roughly a dozen places —
`UIAlertController` for permission-denied dialogs,
`SFSafariViewController` for the in-app browser,
`UIDocumentPickerViewController` for the file chooser, and so on.
`UIView` cannot present view controllers, so the refactor needs to
route every one of these calls to a real `UIViewController`.

There are two sub-problems, and **the existing SDK already solves the
harder one**:

1. *Which* `UIViewController` should host the presentation?
2. *What if* that `UIViewController` is already presenting another
   modal (e.g., a host-app sheet, a previous permission alert, the
   in-app browser)?

For (2), `PMMainViewController` overrides `present(_:animated:)`
([`PMMainViewController.swift:437-456`](../iOS/platinumaps-sdk/ViewControllers/PMMainViewController.swift))
and walks `presentedViewController` to the top of the modal stack
before forwarding the call. This avoids the "Attempt to present X on
Y while Z is presented" warning and is the behaviour we need to
preserve. Note this is not a hypothetical: a host-app modal can be
sitting on top of the map while the WebView triggers a permission
alert asynchronously.

For (1), `PMMapView` walks the responder chain (`self.next` until a
`UIViewController` is reached) to find its owning view controller.
This is the standard UIKit pattern used by SwiftMessages, SVProgressHUD,
and many Flutter plugins (`share_plus`, `firebase_auth`). The chain
yields the same `UIViewController` that hosts the view in both
deployment paths:

- Legacy native-iOS path: the lookup lands on the
  `PMMainViewController` wrapper.
- Flutter path: the lookup lands on the `FlutterViewController`
  hosting the `UiKitView`.

The two sub-problems compose: find the owning `UIViewController`, then
apply the existing topmost-presented walk to it. Concretely:

```swift
extension UIView {
    /// The UIViewController on which `present(_:animated:)` should be
    /// invoked from this view's context, accounting for any modal
    /// chain already in flight.
    var presentationViewController: UIViewController? {
        var responder: UIResponder? = self
        var owner: UIViewController?
        while let r = responder {
            if let vc = r as? UIViewController { owner = vc; break }
            responder = r.next
        }
        guard var top = owner else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }
}
```

This produces the same observable behaviour as the existing override —
the same `UIViewController` ends up calling `present`, just discovered
via the view rather than via `self` — so the refactor does not change
the SDK's presentation semantics. The existing `PMMainViewController`
override is removed because the logic now lives at the `PMMapView`
layer and is applied uniformly.

**Known constraint (unchanged from current SDK):** when the owning
view controller is not yet in a window hierarchy, `UIKit` cannot
present modally. The current SDK has the same constraint
(`PMMainViewController` cannot present before it is in a window),
and the SDK's presentation calls fire in response to user actions or
sensor callbacks that necessarily occur after the view is on screen.
No new risk is introduced.

### Backwards compatibility

Existing iOS integrators use `PMMainViewController` directly (see
[`iOS/README.md`](../iOS/README.md)). After the refactor:

- Every public property (`mapSlug`, `mapQuery`, `mapLocale`,
  `appStoreId`, `coverImage`, `userId`, `secretKey`, `offsetBottom`,
  `launchURL`, `isWebViewInspectable`) is preserved on
  `PMMainViewController`. The wrapper forwards each into its child
  `PMMapView`.
- `PMMainViewControllerDelegate` (currently exposing `openLink`) remains
  the way native callers customise link handling.
- The package's `Package.swift` continues to expose
  `PMMainViewController` as the documented entry point.

A regression pass against the public API (manual smoke test of the
existing iOS sample integration described in `iOS/README.md`) gates the
refactor.

## 5. Flutter plugin

### Android

- Single `FlutterPlugin` implementation registered in `pubspec.yaml`.
- `PlatformViewFactory` returns a `PlatformView` whose `getView()` is a
  configured `PmWebView`. Configuration arrives once via the creation
  arguments (`PmMapOptions`).
- The plugin implements `ActivityAware`, `PluginRegistry.RequestPermissionsResultListener`,
  and `PluginRegistry.ActivityResultListener` so the host app does **not**
  need to forward Activity callbacks itself. This is a strict
  ergonomics improvement over the existing native Android SDK, which
  requires the host to wire five lifecycle callbacks manually
  (see CLAUDE.md §"Lifecycle contract").
- `activityPause` / `activityResume` / `activityDestroy` are driven from
  `ActivityAware` and `FlutterPlugin` shutdown.

### iOS

- Single Swift `FlutterPlugin` registers a
  `FlutterPlatformViewFactory`.
- The factory returns a `FlutterPlatformView` whose `view()` is the
  refactored `PMMapView`. Configuration arrives once via the creation
  arguments.
- No host-app lifecycle wiring required; `PMMapView` self-installs the
  same NotificationCenter observers `PMMainViewController` did.

### Dart API (first cut)

```dart
class PlatinumapsMapView extends StatelessWidget {
  const PlatinumapsMapView({
    super.key,
    required this.mapSlug,
    this.queryParams,
    this.locale,
    this.appStoreId,
    this.userId,
    this.secretKey,
    this.offsetBottom = 0,
    this.coverImage,
    this.beacon,
    this.launchUrl,
    this.onOpenLink,
  });

  /// The map identifier appended to https://platinumaps.jp/maps/.
  /// May include a sub-path (e.g. "demo/sr999"). Serialized as
  /// `mapSlug` on iOS and `mapPath` on Android (the two native SDKs
  /// disagree on the name; see §8).
  final String mapSlug;

  final Map<String, String>? queryParams;
  final PlatinumapsLocale? locale;
  final String? appStoreId;
  final String? userId;
  final String? secretKey;
  final int offsetBottom;

  /// iOS-only. The existing iOS SDK draws this image on top of the
  /// WebView until `web.ready` fires. The Android SDK has no
  /// equivalent today; passing a value on Android is silently
  /// ignored. See §8 for the cross-platform parity question.
  final ImageProvider? coverImage;

  final PlatinumapsBeaconOptions? beacon;

  /// Initial deep-link URL the host captured from a Universal Link or
  /// Custom URL Scheme. The web layer consumes it once it is ready.
  /// Runtime pushes (the equivalent of iOS `pushLaunchURL`) are not
  /// supported in v1; rebuild the widget with a new `launchUrl` to
  /// retrigger.
  final Uri? launchUrl;

  final void Function(Uri url, {required bool sharedCookie})? onOpenLink;
}

class PlatinumapsBeaconOptions {
  const PlatinumapsBeaconOptions({
    required this.uuid,
    this.minSample,
    this.maxHistory,
    this.memo,
  });
  final String uuid;
  final int? minSample;
  final int? maxHistory;
  final String? memo;
}

/// Wire values match the `culture` query parameter the web app expects.
/// Kept in sync with iOS `PMLocale` (see iOS/platinumaps-sdk/Types/PMLocale.swift).
enum PlatinumapsLocale {
  ja,    // "ja"
  en,    // "en"
  zhHans, // "zh-cn"
  zhHant, // "zh-tw"
  ko,    // "ko"
  fr,    // "fr"
  es,    // "es"
  vi,    // "vi"
  id,    // "id"
  my,    // "my"
  th,    // "th"
}
```

`onOpenLink` mirrors `PMMainViewControllerDelegate.openLink`. Other
customer-facing hooks are deliberately omitted (see Non-goals §1).
The iOS `isWebViewInspectable` flag is intentionally not surfaced in
v1; Android already gates the WebView inspector on `BuildConfig.DEBUG`
automatically, and uniform debug-only behaviour is acceptable for the
first release.

### Distribution

In-repo development uses relative paths from `Flutter/` to the
existing `Android/platinumaps-sdk` and root-level `Package.swift`.
That arrangement does **not** survive `dart pub publish`: only the
contents of `Flutter/` are uploaded, so consumers downloading the
package from pub.dev see no `Android/` or `Package.swift` next to
their copy.

The published package therefore needs to carry the native SDK code
itself. Three options are on the table, none yet selected:

| Option | Android | iOS | Trade-off |
|--------|---------|-----|-----------|
| **Bundle sources at publish time** | Copy `Android/platinumaps-sdk` Kotlin sources into `Flutter/android/src/main/kotlin/...` as part of the publish workflow | Copy the iOS Swift sources into `Flutter/ios/Classes/...` and declare them as `source_files` in the podspec | Largest published artifact; in-repo and on-pub.dev layouts diverge; publish workflow must enforce parity |
| **Bundle prebuilt artifacts** | Drop `platinumaps-sdk-release.aar` into `Flutter/android/libs/` and reference it as a flat-dir Gradle dependency | Vendor a prebuilt `xcframework` and reference it from the podspec | No source on pub.dev (harder to debug for consumers); has to be rebuilt for each release |
| **External artifact repositories** | Publish the AAR to Maven Central (or a private Maven repo) and depend on it as a normal Gradle coordinate | Publish a separate CocoaPod, or rely on the existing Swift Package via a podspec that bridges to SPM | Cleanest separation; requires standing up and maintaining the publishing pipeline; ties release cadences across two artifacts |

Whatever option is chosen, the in-repo development experience is
preserved: developers continue to edit `Android/platinumaps-sdk` and
`iOS/platinumaps-sdk` directly, and the publish workflow handles the
translation to pub.dev's shape. The decision is tracked as an open
question (§8).

## 6. PlatformView composition checks

PlatformView lets the Flutter host stack widgets on top of the native
WebView, which is one of the main reasons to ship a Flutter SDK at all.
Three composition cases must be verified before v1 lands; none are
expected to be blockers but each deserves an explicit check:

1. **Cover image vs Flutter splash.** The native SDK draws its own
   cover image on top of the WebView until `web.ready`. A Flutter host
   that places its own splash widget over the map will need a clear
   rule for which one wins. Document the existing native cover image
   as authoritative; the host may pass `coverImage: null` and own the
   splash entirely.
2. **Native modals.** `UIAlertController` (iOS) and the file-chooser
   `Intent` (Android) present above everything, including Flutter
   overlays. This is the desired behaviour for permission prompts and
   needs no special handling.
3. **Gesture conflicts.** Flutter widgets placed in a `Stack` above the
   PlatformView must not steal touches intended for the map. The
   recommended pattern is `IgnorePointer` on full-bleed decorations and
   explicit gesture detectors only on UI elements that need them. Call
   this out in `Flutter/README.md`.

## 7. Verification & release criteria

The SDK is considered complete when an external Flutter developer can
install it from pub.dev, follow `Flutter/README.md`, and have a working
embedded map in their app on both supported platforms. Reaching that
bar requires several layers of verification beyond "the sample app
runs".

### Test pyramid

| Layer | Scope | Tooling |
|-------|-------|---------|
| Dart unit tests (`test/`) | Pure-Dart logic: options serialization, URL building, public API contracts, callback dispatch with a mocked platform channel | `flutter test` |
| Native plugin unit tests | The thin plugin glue layer only (PlatformViewFactory creation arguments, MethodChannel routing). Existing iOS/Android SDK modules retain their own test posture independently. | Android: JUnit / Robolectric. iOS: XCTest |
| Integration tests (`integration_test/`) | End-to-end behaviour from the example app: WebView reaches `web.ready`, `onOpenLink` fires for whitelisted schemes, beacon configuration round-trips correctly through the bridge. | `flutter test integration_test` driven from the example app, runnable on emulators / simulators in CI and on physical devices for sensor-dependent checks |
| Manual smoke checks | Hardware-only flows that CI cannot exercise reliably: GPS fix on a moving device, iBeacon ranging against real hardware, camera-backed file chooser. | Physical iOS + Android devices, captured in a release checklist |

Test coverage is reported per pull request but **no numerical gate is
enforced** — coverage is a signal, not the goal. The integration tests
are the primary safety net.

### Example app (`Flutter/example/`)

The example app is both the user-facing reference integration and the
host for `integration_test`. It must:

- Demonstrate every public API on `PlatinumapsMapView`, including
  `onOpenLink`, beacon configuration, cover image, and a Flutter
  widget overlaid above the map.
- Build for iOS and Android out of the box with `flutter run` against
  the example directory.
- Be the only sample integration we ship; we do not maintain separate
  per-feature samples.

### Static analysis & continuous integration

- `flutter analyze` and `dart format --output=none
  --set-exit-if-changed` must pass with zero warnings on every PR.
- A `pana` run is part of CI. The target is the highest pub.dev tier
  for each scoring category that pana exposes (documentation,
  platform support, conventions, static analysis, dependencies,
  support). Numerical caps shift with pana releases; we track the
  category-level result rather than an absolute score.
- CI matrix: Flutter stable + current beta; iOS 16 and the current
  iOS release; Android API 24 (minimum supported) and the current
  stable API. Adding a new minimum-supported version triggers a
  changelog entry.

### Documentation

- `Flutter/README.md` — integration guide structured like the existing
  iOS / Android READMEs (install, minimum versions, required
  permissions, lifecycle contract, minimal usage example, FAQ).
- Public Dart API carries dartdoc comments. `dart doc` produces clean
  output with no broken references.
- `CHANGELOG.md` at the package root follows the
  [Keep a Changelog](https://keepachangelog.com) format and is updated
  in the same PR that introduces a user-visible change.

### Release readiness checklist

Before the first publish, all of the following must hold:

- [ ] Unit + integration test suites green on CI for the supported
      matrix.
- [ ] `flutter analyze` clean; `pana` score at target tier.
- [ ] Manual smoke checks for sensor-dependent flows recorded against
      the release candidate.
- [ ] All public APIs documented; `dart doc` produces no warnings.
- [ ] `Flutter/README.md` integration walkthrough has been followed
      end-to-end by someone who did not write the SDK.
- [ ] `CHANGELOG.md`, `pubspec.yaml` version, and the package
      `LICENSE` are up to date.
- [ ] The example app builds and runs on iOS and Android against the
      release candidate.

### Versioning & distribution

The package follows semantic versioning. The bridge protocol's
user-agent suffix (`Platinumaps/2.0.0`, see CLAUDE.md §Versioning) is
**not** the package's version — the Flutter SDK's `pubspec.yaml`
version tracks the package itself and starts at `0.1.0` while the
public API is still considered unstable. The package is published to
pub.dev once the readiness checklist passes; pre-1.0 versions may
introduce breaking changes with a clear CHANGELOG entry.

## 8. Open questions

1. **`PMMapView` lifecycle granularity.** `didMoveToWindow` fires every
   time the view re-enters a window hierarchy, not only on first
   attach. Confirm that the first-attach latch in the refactor
   preserves the current `viewDidAppear`-once behaviour.
2. **Beacon configuration timing.** The native SDK accepts beacon
   options at `openPlatinumaps` time and treats them as immutable for
   the WebView's lifetime. Confirm that the Flutter creation-arguments
   path matches this contract (i.e., changing
   `PlatinumapsBeaconOptions` after construction either rebuilds the
   PlatformView or is documented as a no-op).
3. **CocoaPods vs Swift Package Manager.** Flutter iOS plugins
   historically ship as podspecs. Confirm whether bundling a podspec
   that re-exports the existing Swift Package is acceptable, or
   whether we need a podspec that vendors the sources directly.
4. **Native SDK packaging for pub.dev.** Pick one of the three
   options enumerated in §5 *Distribution* (source bundling, prebuilt
   artifact vendoring, external artifact repositories). The choice
   shapes the publish workflow and the consumer's `flutter pub get`
   footprint.
5. **Cover image parity.** Decide whether to add Android coverage
   for `coverImage` in the existing Android SDK, or freeze
   `PlatinumapsMapView.coverImage` as iOS-only in the Dart API and
   document the asymmetry.
6. **Naming alignment between iOS and Android.** The native SDKs
   disagree on field names — iOS `mapSlug` / Android `mapPath`, iOS
   `mapQuery` / Android `queryParams`. The Dart API picks one of each
   (`mapSlug`, `queryParams`) and the plugin glue translates. Decide
   whether to also rename in the native SDKs to converge, or to leave
   the divergence in place forever.
7. **`PlatinumapsLocale` wire format.** The enum values map to web-app
   `culture` strings (`"ja"`, `"zh-cn"`, …). Confirm Kotlin and Swift
   serialize identically, including the hyphenated forms, when the
   Dart enum is sent through the platform channel.
8. **Permission acquisition responsibility.** The existing iOS and
   Android SDKs trigger system permission prompts themselves
   (`CLLocationManager`, `ActivityCompat.requestPermissions`).
   Confirm the Flutter wrapper inherits this behaviour as-is and that
   the host only needs to declare `NSLocationWhenInUseUsageDescription`
   / `ACCESS_FINE_LOCATION` etc. in its `Info.plist` /
   `AndroidManifest.xml`, with no `permission_handler` dependency.
9. **`isWebViewInspectable` exposure.** The iOS SDK has a public
   opt-in for the WebKit Inspector. v1 omits it from the Dart API on
   the assumption that debug-only behaviour (Android already gates on
   `BuildConfig.DEBUG`) is sufficient. Reopen if customers ask for
   release-build debugging.

## 9. Roadmap

| Step | Description | Gate | Parallelizable with |
|------|-------------|------|---------------------|
| 0 | Design review of this document; open questions in §8 closed or explicitly deferred | Sign-off recorded in the reviewing thread | — |
| 1a | Refactor iOS SDK: extract `PMMapView`, shrink `PMMainViewController` to a forwarding wrapper | Existing iOS sample integration passes a manual smoke test against unchanged `iOS/README.md` instructions | 1b |
| 1b | Android side of plugin scaffolding (`Flutter/android/` Gradle project, `PlatformViewFactory` wrapping `PmWebView`, Dart skeleton) | Plugin builds; example app launches an empty `PlatinumapsMapView` on Android | 1a |
| 2 | iOS side of plugin scaffolding wired to the refactored `PMMapView` | Example app launches an empty `PlatinumapsMapView` on iOS | — (depends on 1a) |
| 3 | Wire configuration, cover image, `onOpenLink` callback through to both platforms | Example app loads a real map slug end-to-end on both platforms | — |
| 4 | Activity lifecycle forwarding (Android) and `ActivityAware` plumbing | Background / foreground / destroy cycle verified | 5 |
| 5 | PlatformView composition checks (§6) and `Flutter/README.md` | All three cases documented with working snippets | 4 |
| 6 | Test suite: Dart unit tests + native plugin-glue tests + `integration_test` driven from the example app | Tests green on CI matrix (§7) | — |
| 7 | Static analysis + dartdoc + `pana` pass | Zero analyzer warnings; `pana` category targets met (§7) | — |
| 8 | Release readiness checklist (§7) | All checklist items satisfied; first pub.dev publish | — |

Step 0 is a hard gate: implementation does not start until the design
review has signed off and the §8 open questions have been resolved or
explicitly deferred. After step 0, the Android plugin scaffold (1b)
can run in parallel with the iOS refactor (1a), and steps 4 and 5 can
overlap.
