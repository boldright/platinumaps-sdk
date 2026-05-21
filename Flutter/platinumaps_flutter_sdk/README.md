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

Once published to pub.dev: `platinumaps_flutter_sdk: ^0.1.0`.

### 2. iOS deployment target — `ios/Podfile`

```ruby
platform :ios, '16.0'
```

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

### 4. Android minimum SDK — `android/app/build.gradle`

```gradle
android {
    defaultConfig {
        minSdk 24
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
| `userId` | Opaque user identifier exposed to the web layer | ✓ | — |
| `secretKey` | Opaque shared secret exposed to the web layer | ✓ | — |
| `offsetBottom` | Flag-style switch: non-zero tells the web layer to treat the bottom safe-area inset as `0` (the integer value is not used as a pixel distance — only its zero/non-zero quality matters today) | ✓ | — |
| `beacon` | iBeacon ranging configuration | ✓ | ✓ |
| `launchUrl` | Deep link forwarded to the web layer at first load | ✓ | — |
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

```dart
final controller = PlatinumapsMapController();

PlatinumapsMapView(
  controller: controller,
  mapSlug: 'demo',
)

// Later — for example, a Universal Link arrived after the map mounted:
await controller.pushLaunchUrl(uri);
```

Available methods today:
- `pushLaunchUrl(Uri url)` — mirror of the iOS native SDK's
  `PMMapView.pushLaunchURL(_:)`. The URL is forwarded to the web
  layer via `app.link`; if `web.ready` has not yet fired the native
  side stashes the URL and replays it as soon as it arrives.

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
  runtime operations (e.g. `setLocale`) are still rebuild-only.
- **No bidirectional bridge for arbitrary commands.** The Dart side
  cannot send arbitrary `command://` calls into the WebView; only
  the configuration knobs and controller methods listed above are
  exposed.

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
