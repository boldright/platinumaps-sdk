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
