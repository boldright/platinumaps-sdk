# Platinumaps Flutter SDK

Embed the [Platinumaps](https://platinumaps.jp) web map in a Flutter
app. The Flutter SDK is a thin wrapper around the existing native iOS
and Android SDKs in this repository (`iOS/`, `Android/`); see
[`DESIGN.md`](DESIGN.md) for the architecture.

> Status: pre-release scaffold. The package is not yet on pub.dev.

## Requirements

- Flutter 3.32 or later (Dart 3.8 or later — `^3.8.0` in `pubspec.yaml`)
- iOS 16+
- Android API 24+ (Android 7.0)

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

Once published to pub.dev: `platinumaps_flutter_sdk: ^0.1.0`.

### 2. iOS deployment target — `ios/Podfile`

```ruby
platform :ios, '16.0'
```

The default Flutter template uses iOS 12 or 13; pod resolution fails
with confusing errors if it stays below 16.

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

### Troubleshooting

- **`Module 'platinumaps_flutter_sdk' not found` on iOS.** Flutter
  caches its SwiftPM-generated artifacts; bumping the SDK or the
  iOS deployment target sometimes leaves stale caches behind. Run
  `flutter clean && flutter pub get` and rebuild.
- **Activity lifecycle / permission callbacks.** The bare native
  Android SDK requires the host activity to forward five callbacks
  (`onPause`, `onResume`, `onDestroy`, `onRequestPermissionsResult`,
  `onActivityResult`) into `PmWebView`. The Flutter plugin does this
  forwarding automatically via `ActivityAware` — the host Flutter
  app needs no extra plumbing.

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

`PlatinumapsMapView` is a regular Flutter widget, so it composes
naturally with `Stack`, `Padding`, `SafeArea`, etc. To overlay your
own UI on top of the map, wrap it in a `Stack`. Use `IgnorePointer`
on full-bleed decorations so they do not steal gestures intended for
the map.

## Configuration

| Parameter | Description | iOS | Android |
|-----------|-------------|-----|---------|
| `mapSlug` *(required)* | Path appended to `https://platinumaps.jp/maps/` | ✓ | ✓ |
| `queryParams` | Extra query string entries on the map URL | ✓ | ✓ |
| `locale` | Forces the map UI language | ✓ | ✓ |
| `appStoreId` | App Store ID consumed by `app.review` | ✓ | — |
| `userId` | Opaque user identifier exposed to the web layer | ✓ | — |
| `secretKey` | Opaque shared secret exposed to the web layer | ✓ | — |
| `offsetBottom` | Reports a zeroed bottom safe-area inset to the web | ✓ | — |
| `beacon` | iBeacon ranging configuration | ✓ | ✓ |
| `launchUrl` | Deep link forwarded to the web layer at first load | ✓ | — |

Fields marked `—` are accepted by the Dart API for forward
compatibility but currently ignored on that platform.

The iOS native SDK exposes a `coverImage` (splash) API. The Flutter
SDK deliberately does not — drive the splash from the Flutter host:
compose your splash widget above the map in a `Stack`, or delay
mounting `PlatinumapsMapView` until your host-side splash finishes.

### Updating configuration at runtime

Every field except `onOpenLink` is forwarded to the native side once,
at PlatformView creation. Mutating Dart state (e.g. switching `locale`
in a settings screen) **does not** restart the WebView with the new
value — the existing PlatformView keeps the configuration it was
constructed with.

The idiomatic Flutter pattern is to drive a rebuild from a key:

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
PlatformView and constructs a new one, picking up the new
configuration. `onOpenLink` is the one exception: its closure is
re-read on every method-channel callback, so swapping handlers does
not require a rebuild.

## Known limitations

- **No runtime `launchUrl` push.** The iOS native SDK exposes
  `pushLaunchURL(_:)` for forwarding a Universal Link or Custom URL
  Scheme that arrives *after* the map is on screen. The Flutter SDK
  does not surface that yet — rebuild the widget with a new
  `launchUrl` (and a fresh key) to trigger the same flow. A
  `PlatinumapsMapController` handle is on the v1.0 wishlist.
- **No bidirectional bridge.** The Dart side cannot send arbitrary
  `command://` calls into the WebView; only the configuration knobs
  listed above are forwarded.

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
