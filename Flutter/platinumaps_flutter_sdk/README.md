# Platinumaps Flutter SDK

Embed the [Platinumaps](https://platinumaps.jp) web map in a Flutter
app. The Flutter SDK is a thin wrapper around the existing native iOS
and Android SDKs in this repository (`iOS/`, `Android/`); see
[`DESIGN.md`](DESIGN.md) for the architecture.

> Status: pre-release scaffold. The package is not yet on pub.dev.

## Requirements

- Flutter 3.32 or later (Dart 3.8 or later — `^3.8.0` in `pubspec.yaml`)
- iOS 16+ — matches the bundled iOS native SDK, which uses Swift
  Concurrency and WebKit APIs that landed in iOS 16
- Android API 24+ (Android 7.0) — matches the bundled Android native
  SDK's `minSdk`

## Quick start

The five blocks below are everything a host application has to change
to embed the SDK. Add only the permission entries that correspond to
features your map actually uses.

### 1. Dependency — `pubspec.yaml`

```yaml
dependencies:
  platinumaps_flutter_sdk:
    git:
      url: https://github.com/boldright/platinumaps-sdk
      path: Flutter/platinumaps_flutter_sdk
```

When iterating on the SDK and a host app side-by-side, point at
your local checkout instead:

```yaml
dependencies:
  platinumaps_flutter_sdk:
    path: ../../platinumaps-sdk/Flutter/platinumaps_flutter_sdk
```

Once published to pub.dev: `platinumaps_flutter_sdk: ^1.0.0`.

### 2. iOS deployment target — `ios/Podfile` **and** Xcode

```ruby
platform :ios, '16.0'
```

Also raise the Xcode-side deployment target: open `ios/Runner.xcworkspace`,
select the **Runner** target, and set **Minimum Deployments → iOS** to
`16.0` (or higher). `flutter create` defaults this to `13.0`, and the
Swift Package Manager resolver — used since Flutter 3.32 — refuses to
link the plugin with:

> Target Integrity: The package product 'platinumaps-flutter-sdk'
> requires minimum platform version 16.0 for the iOS platform, but
> this target supports 13.0.

`platform :ios, '16.0'` in the Podfile only governs the CocoaPods-side
resolution; the Xcode project setting is independent.

### 3. iOS usage descriptions — `ios/Runner/Info.plist`

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to show your position on the map.</string>
<key>NSCameraUsageDescription</key>
<string>Used by the map's camera-backed features.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used when the map records audio.</string>
```

`NSBluetoothAlwaysUsageDescription` is *not* required: the SDK ranges
iBeacons through `CLLocationManager`, not `CBCentralManager`.

### 4. Android minimum SDK — `android/app/build.gradle.kts`

```kotlin
android {
    defaultConfig {
        minSdk = 24
    }
}
```

### 5. Android permissions — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<!-- Only if you enable iBeacon ranging. -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
<!-- Legacy bluetooth permissions for API < 31. -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30"/>
```

`BLUETOOTH_CONNECT` is *not* required — the SDK only scans for
beacons, it does not establish GATT connections.

### Note: Activity lifecycle / permission callbacks (Android)

The bare native Android SDK requires the host activity to forward
five callbacks (`onPause`, `onResume`, `onDestroy`,
`onRequestPermissionsResult`, `onActivityResult`) into `PmWebView`.
The Flutter plugin does this forwarding automatically via
`ActivityAware` — the host Flutter app needs no extra plumbing.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PlatinumapsMapView(
          mapSlug: 'demo',
          locale: PlatinumapsLocale.ja,
          beacon: const PlatinumapsBeaconOptions(
            uuid: '00000000-0000-0000-0000-000000000000',
          ),
          onOpenLink: (Uri url, {required bool sharedCookie}) {
            // Hand the link off to the host's preferred browser.
          },
        ),
      ),
    );
  }
}
```

`PlatinumapsMapView` is a regular Flutter widget. A runnable example
with overlay composition and `onOpenLink` plumbing lives in
[`example/`](../example/).

## Configuration

| Parameter | Description | iOS | Android |
|-----------|-------------|-----|---------|
| `mapSlug` *(required)* | Path appended to `https://platinumaps.jp/maps/` | ✓ | ✓ |
| `queryParams` | Extra query string entries on the map URL (keys are interpreted by the web layer — see the Platinumaps web docs) | ✓ | ✓ |
| `locale` | Forces the map UI language | ✓ | ✓ |
| `appStoreId` | App Store ID consumed by `app.review` | ✓ | — |
| `userId` | Opaque user identifier exposed to the web layer | ✓ | ✓ |
| `secretKey` | Opaque shared secret exposed to the web layer | ✓ | ✓ |
| `safeAreaTop`, `safeAreaBottom` | Safe-area insets (logical pixels) forwarded to the web layer. Pass `MediaQuery.of(context).padding.top` / `.bottom` when the map fills the screen; pass `0` when the host already draws above / below the map (e.g. an `AppBar`) | ✓ | ✓ |
| `beacon` | iBeacon ranging configuration | ✓ | ✓ |
| `launchUrl` | Deep link forwarded to the web layer at first load | ✓ | ✓ |
| `controller` | [`PlatinumapsMapController`](#updating-configuration-at-runtime) handle for runtime operations | ✓ | ✓ |

Fields marked `—` are accepted by the Dart API for forward
compatibility but currently ignored on that platform.

The iOS native SDK exposes a `coverImage` (splash) API. The Flutter
SDK deliberately does not — drive the splash from the Flutter host:
compose your splash widget above the map in a `Stack`, or delay
mounting `PlatinumapsMapView` until your host-side splash finishes.

### Updating configuration at runtime

Constructor fields are forwarded to the native side once, at
PlatformView creation. There are two ways to apply changes after
the widget is on screen:

**1. Runtime push via `PlatinumapsMapController`.** Attach a
controller and call its methods to drive the map without losing
the WebView's scroll position, selected spot, or session cookies.

Hold the controller in a `State` field — constructing it inside
`build()` would create a fresh, unattached instance on every
rebuild and silently drop your `pushLaunchUrl` calls.

One controller drives exactly one `PlatinumapsMapView`. Passing the
same controller to two widgets fires an assert in debug builds; give
each widget its own controller instead.

```dart
class _MapScreenState extends State<MapScreen> {
  final _controller = PlatinumapsMapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlatinumapsMapView(
      controller: _controller,
      mapSlug: 'demo',
    );
  }

  // Later — for example, a Universal Link arrived after the map mounted:
  Future<void> _onLink(Uri uri) => _controller.pushLaunchUrl(uri);
}
```

Available methods today:
- `pushLaunchUrl(Uri url)` — mirror of the iOS native SDK's
  `PMMapView.pushLaunchURL(_:)`. The URL is forwarded to the web
  layer via `app.link`; if `web.ready` has not yet fired the native
  side stashes the URL and replays it as soon as it arrives. Calls
  made before the controller is attached to a widget are also
  stashed and replayed on attach, so it is safe to call this in the
  same frame the host mounts the `PlatinumapsMapView`.

**2. Widget rebuild with a fresh key** (for fields that the
controller does not yet cover, like `locale` or `beacon`):

```dart
PlatinumapsMapView(
  key: ValueKey('$mapSlug|${locale?.code}|${beacon?.uuid}'),
  mapSlug: mapSlug,
  locale: locale,
  beacon: beacon,
  ...
)
```

When any of the keyed inputs change, Flutter discards the old
PlatformView and constructs a new one — which **resets the WebView**
(scroll position, session cookies, selected spot all gone). Prefer
the controller approach where it exists.

`onOpenLink` is re-read on every method-channel callback, so
swapping that closure never requires a rebuild.

## Known limitations

- **`PlatinumapsMapController` covers `pushLaunchUrl` only.** Other
  runtime operations (e.g. `setLocale`, toggling `beacon`, updating
  `queryParams`) still require a widget rebuild with a fresh key,
  which resets the WebView. Controller-based runtime updates are on
  the roadmap (DESIGN.md "Open / future").
- **No bidirectional bridge for arbitrary commands.** The Dart side
  cannot send arbitrary `command://` calls into the WebView; only
  the configuration knobs and controller methods listed above are
  exposed.
- **`onOpenLink` with `sharedCookie: true` needs a custom in-app
  browser on the Flutter side.** The native iOS / Android SDKs ship
  `PMWebViewController` / `WebBrowserActivity` for this, but the
  Flutter plugin does not yet expose them. Until then, hosts that
  emit shared-cookie links (e.g. stamp-rally reward downloads) must
  wire up a cookie-sharing in-app WebView themselves.
- **`appStoreId` is iOS-only.** It drives `UIApplication.open` against
  the App Store review page; the Android SDK uses the Play Store URL
  resolved from the application id, so the field is ignored on
  Android.

## Sample app

A runnable sample lives at [`example/`](../example/). It mounts a
`PlatinumapsMapView` against the public demo map, wires `onOpenLink`
through `url_launcher`, and stacks a small Flutter overlay above the
PlatformView so the gesture-passthrough composition case is exercised
end-to-end.

## Reporting issues

File an issue at
[github.com/boldright/platinumaps-sdk/issues](https://github.com/boldright/platinumaps-sdk/issues).

## License

MIT — see [LICENSE](LICENSE).
