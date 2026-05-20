# Platinumaps Flutter SDK

Embed the [Platinumaps](https://platinumaps.jp) web map in a Flutter
app. The Flutter SDK is a thin wrapper around the existing native iOS
and Android SDKs in this repository (`iOS/`, `Android/`); see
[`DESIGN.md`](DESIGN.md) for the architecture.

> Status: pre-release scaffold. The package is not yet on pub.dev.

## Requirements

- Flutter 3.32 or later (Dart 3.8+)
- iOS 16+
- Android API 24+ (Android 7.0)

## Installation

Once published to pub.dev:

```yaml
dependencies:
  platinumaps_flutter_sdk: ^0.1.0
```

While the package is in pre-release, depend on it via Git:

```yaml
dependencies:
  platinumaps_flutter_sdk:
    git:
      url: https://github.com/boldright/platinumaps-sdk
      path: Flutter
```

## Required permissions

The SDK consumes a small set of device capabilities and triggers the
platform permission prompts itself. The host application must
declare the underlying entries:

Keep only the entries that correspond to features the map you ship
actually uses — leaving an unused declaration in place is harmless
but bloats the App Store / Play Console permission disclosure.

### iOS — `Info.plist`

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to show your position on the map.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used to detect iBeacons configured by the map operator.</string>
<key>NSCameraUsageDescription</key>
<string>Used by the map's camera-backed features.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used when the map records audio.</string>
```

`NSMicrophoneUsageDescription` is required even if you only plan to
use the camera, because iOS surfaces the microphone prompt for any
`getUserMedia({ video: true })` call the embedded web layer might
make.

### Android — `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<!-- Legacy bluetooth permissions for API < 31. -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

`example/android/app/src/main/AndroidManifest.xml` is a complete
reference that you can copy from.

The bare native Android SDK requires the host activity to forward
five lifecycle callbacks (`onPause`, `onResume`, `onDestroy`,
`onRequestPermissionsResult`, `onActivityResult`) into `PmWebView`.
The Flutter plugin does this forwarding automatically via
`ActivityAware`, so **the host Flutter app needs no extra plumbing**.

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
          onOpenLink: (url, {required sharedCookie}) {
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
| `coverImage` | Splash image shown until `web.ready` | — | — |
| `beacon` | iBeacon ranging configuration | ✓ | ✓ |
| `launchUrl` | Deep link forwarded to the web layer at first load | ✓ | — |

Fields marked `—` are accepted by the Dart API for forward
compatibility but currently ignored on that platform. `coverImage`
is dropped on both platforms in v0.1; render a Flutter splash widget
above the map in a `Stack` until the parity work in `DESIGN.md`
§8 #5 lands. The cross-platform parity backlog tracks the rest.

## Sample app

A runnable sample lives at [`example/`](example/). It mounts a
`PlatinumapsMapView` against the public demo map, wires `onOpenLink`
through `url_launcher`, and stacks a small Flutter overlay above the
PlatformView so the gesture-passthrough composition case from
DESIGN.md §6 is exercised end-to-end.

## Reporting issues

File an issue at
[github.com/boldright/platinumaps-sdk/issues](https://github.com/boldright/platinumaps-sdk/issues).

## License

MIT — see [LICENSE](LICENSE).
