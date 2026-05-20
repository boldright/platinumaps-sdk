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
- **Federated plugin layout.** v1 ships as a single non-federated package
  to keep the surface small.
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
|   ├── PlatformViewLink (Android)                   |
|   ├── UiKitView         (iOS)                      |
|   └── MethodChannel: jp.co.boldright.platinumaps   |
|         (config push, openLink callback, lifecycle)|
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
    this.onOpenLink,
  });

  final String mapSlug;
  final Map<String, String>? queryParams;
  final PlatinumapsLocale? locale;
  final String? appStoreId;
  final String? userId;
  final String? secretKey;
  final int offsetBottom;
  final ImageProvider? coverImage;
  final PlatinumapsBeaconOptions? beacon;
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

enum PlatinumapsLocale { ja, en, zhHans, zhHant, ko }
```

`onOpenLink` mirrors `PMMainViewControllerDelegate.openLink`. Other
customer-facing hooks are deliberately omitted (see Non-goals §1).

### Distribution

Both halves of the plugin reference the existing native SDKs by
relative path inside this repository — Android via Gradle
`includeBuild` (or a direct `:project` dependency), iOS via the
local `Package.swift`. Consumers install the plugin from pub.dev; the
native SDKs travel with the package and there is no separate Maven /
SPM publish step to coordinate.

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

## 7. Open questions

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

## 8. Roadmap

| Step | Description | Gate |
|------|-------------|------|
| 1 | Refactor iOS SDK: extract `PMMapView`, shrink `PMMainViewController` to a forwarding wrapper | Existing iOS sample integration passes a manual smoke test against unchanged `iOS/README.md` instructions |
| 2 | Create `Flutter/` directory, plugin scaffolding, Dart API skeleton, native plugin glue (both platforms) | Plugin builds; example app launches an empty `PlatinumapsMapView` |
| 3 | Wire configuration, cover image, `onOpenLink` callback | Example app loads a real map slug end-to-end on both platforms |
| 4 | Activity lifecycle forwarding (Android) and `ActivityAware` plumbing | Background / foreground / destroy cycle behaves identically to the existing Android sample |
| 5 | Composition checks (§6) and `Flutter/README.md` | All three cases documented with working snippets |
| 6 | Publish-readiness pass: `pubspec.yaml` metadata, license, example app polish | Ready for first internal pub.dev publish |

Implementation does not start until this document has been reviewed.
