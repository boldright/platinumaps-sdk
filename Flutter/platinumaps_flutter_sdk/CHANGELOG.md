# Changelog

All notable changes to this package are documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased] — towards 0.1.0

Initial pre-release for 0.1.0. The API surface is considered unstable
until 1.0.0. When the release tag is cut, rename this heading to
`## [0.1.0] - YYYY-MM-DD`.

### Added

- `PlatinumapsMapView` widget that embeds the Platinumaps web map via
  a `PlatformView` (`UiKitView` on iOS, `AndroidView` on Android).
  Accepts `mapSlug`, `queryParams`, `locale`, `appStoreId`, `userId`,
  `secretKey`, `offsetBottom`, `beacon`, `launchUrl`, and an
  `onOpenLink` callback. The iOS-only parameters are still accepted
  on Android for forward-compatibility but are silently ignored — see
  `README.md` for the parity table. The iOS native SDK's `coverImage`
  is intentionally not exposed; render the splash from the Flutter
  host instead.
- `PlatinumapsMapController` imperative handle. Attach via the
  widget's `controller:` parameter and call `pushLaunchUrl(Uri)` to
  forward a Universal Link / Custom URL Scheme that arrives after
  the map has mounted, without rebuilding the widget (which would
  lose the WebView's scroll position, session cookies, etc.).
  Mirrors the iOS native SDK's `PMMapView.pushLaunchURL(_:)`.

### Changed

- Android plugin: supports both AGP 8 (Flutter 3.32-3.43) and AGP 9
  (Flutter 3.44+). Host builds on Flutter 3.44 no longer emit the
  KGP deprecation warning.
- `PlatinumapsBeaconOptions` for iBeacon configuration (uuid +
  optional minSample / maxHistory / memo).
- `PlatinumapsLocale` enum covering the eleven languages the
  Platinumaps web layer supports.
- `PlatinumapsOpenLinkCallback` typedef for the host-side
  open-in-app-browser callback.
- `ActivityAware` plumbing on Android: the host Flutter app does not
  need to forward `onPause` / `onResume` / `onDestroy` /
  `onRequestPermissionsResult` / `onActivityResult` callbacks
  manually — the plugin does it automatically.
- iOS and Android native sources ship inside this package, so adding
  the plugin requires no extra dependency on a pre-built AAR or a
  separate native SDK release.
- Example app at `Flutter/example/` demonstrating
  `PlatinumapsMapView` with `onOpenLink` plumbed through
  `url_launcher` and a small Flutter overlay stacked on top of the
  map.
