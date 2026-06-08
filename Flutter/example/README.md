# Platinumaps Flutter SDK example

A runnable Flutter app that embeds the public Platinumaps demo map
through the `platinumaps_flutter_sdk` plugin. Use it to smoke-test
the plugin during development or as a copy-paste reference for the
integration in your own app.

## Running

From this directory:

```bash
flutter pub get
flutter run
```

To target a specific device, list the available ones first
(`flutter devices`) and then `flutter run -d <id>`.

## What it demonstrates

- Mounting a `PlatinumapsMapView` against the `demo` map.
- Forwarding `onOpenLink` URLs to the system browser via
  [`url_launcher`](https://pub.dev/packages/url_launcher).
- Composing a Flutter overlay above the PlatformView in a `Stack`
  while keeping map gestures untouched.

For the full integration guide see
[`../platinumaps_flutter_sdk/README.md`](../platinumaps_flutter_sdk/README.md).
The runtime permissions declared in
`android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`
are the same set the integration guide asks host apps to copy.
