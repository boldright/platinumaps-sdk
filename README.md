# Platinumaps SDK

Native iOS and Android SDKs that embed the [Platinumaps](https://platinumaps.jp)
web application inside a `WKWebView` / `WebView` and bridge the limited set
of native capabilities the web layer cannot reach on its own — geolocation,
heading, iBeacon ranging, in-app browser, app-store review, file chooser.

The SDK is intentionally minimal: it owns one web view, exposes a small
configuration surface, and exits stage left. The host application supplies
all UI, navigation, auth, and analytics.

## Documentation

- **[iOS integration guide](iOS/README.md)** — Swift Package Manager
  installation, public API, required `Info.plist` entries, delegate hooks.
- **[Android integration guide](Android/README.md)** — `AndroidManifest.xml`
  permissions, `PmWebView` lifecycle contract, sample integration.
- **[CLAUDE.md](CLAUDE.md)** — architecture, bridge protocol, threading
  model, security notes, build instructions. Read this first if you intend
  to modify the SDK.

## Required permissions

The SDK consumes these device capabilities and surfaces the necessary
permission prompts at runtime. The **host application** must declare them
in its manifest / `Info.plist`:

- Location (`When In Use`).
- Camera and microphone (only if the embedded map uses the camera /
  audio capture features).
- Bluetooth scanning (Android only, if iBeacon ranging is enabled).

The platform-specific READMEs list the exact manifest entries.

## License

MIT — see [LICENSE](LICENSE).
