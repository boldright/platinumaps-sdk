# Platinumaps iOS Integration Guide

## Requirements

- Swift 6.0+
- Xcode 16.0+
- iOS 16.0+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/boldright/platinumaps-sdk.git", from: "3.0.0")
```

Or in Xcode: **File → Add Package Dependencies…** and enter the repository
URL.

### Manual integration

Copy the `iOS/platinumaps-sdk/` directory into your Xcode project. The
SDK is self-contained — its localized permission-alert strings are
embedded in `PMLocalizedStrings.swift`, so no resource bundle needs to
be added to the target's **Copy Bundle Resources** build phase.

> **Upgrading from a pre-`PMLocalizedStrings.swift` build:** earlier
> versions of the SDK shipped its localized strings as
> `iOS/platinumaps-sdk/Platinumaps.bundle/`, and the integration guide
> asked hosts to add that bundle to **Copy Bundle Resources**. The
> bundle is no longer part of the SDK — when you pull these sources
> in, remove the stale `Platinumaps.bundle` reference from your
> target's build phases (and from the project tree) so the missing
> file does not break the build.

## Folder structure

```
iOS/platinumaps-sdk
├── Errors/PMError.swift                          ← reserved error type
├── Types/PMLocale.swift                          ← `culture` enum
├── Types/PMLocalizedStrings.swift                ← embedded permission strings
├── ViewControllers
│   ├── PMMainViewController.swift                ← public entry point
│   └── PMWebViewController.swift                 ← in-app browser
├── Views/PMMapView.swift                         ← public map view (UIView)
└── Views/PMWebView.swift                         ← WKWebView (zero insets)
```

## Required `Info.plist` keys

Add the usage descriptions for the capabilities your map actually consumes:

| Key | Required when | Example value |
|-----|---------------|---------------|
| `NSLocationWhenInUseUsageDescription` | always | "Used to show your position on the map." |
| `NSCameraUsageDescription` | the map uses the camera (QR codes, AR) | "Used to scan QR codes inside the map." |
| `NSMicrophoneUsageDescription` | the map records audio | "Used to record audio messages." |
| `NSBluetoothAlwaysUsageDescription` | iBeacon ranging is enabled | "Used to detect indoor positioning beacons." |

The SDK uses standard HTTPS to `platinumaps.jp`, so no App Transport
Security exception is required.

## Integration

1. Import the package.
2. Instantiate `PMMainViewController`, set `mapSlug`, present it.

```swift
import UIKit
import PlatinumapsSDK
import SafariServices

class HostViewController: UIViewController {

    @IBAction func openPlatinumaps(_ sender: Any) {
        let vc = PMMainViewController()
        vc.mapSlug = "demo"
        vc.mapQuery["key1"] = "value1"
        vc.delegate = self
        let nc = UINavigationController(rootViewController: vc)
        present(nc, animated: true)
    }
}

extension HostViewController: PMMainViewControllerDelegate {
    func openLink(_ url: URL, sharedCookie: Bool) {
        if sharedCookie {
            // Shared-cookie links (stamp-rally rewards, etc.) must keep the
            // platinumaps.jp session — present an in-app browser that
            // shares cookies with the SDK's WKWebView.
            let vc = PMWebViewController()
            vc.pageUrl = url
            present(UINavigationController(rootViewController: vc),
                    animated: true)
        } else {
            // Anything else may be handed to SFSafariViewController.
            present(SFSafariViewController(url: url),
                    animated: true,
                    completion: nil)
        }
    }
}
```

## Public API

### `PMMainViewController`

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `mapSlug` | `String?` | ✓ | URL slug. Final URL is `https://platinumaps.jp/maps/<mapSlug>`. |
| `mapQuery` | `[String: String]` | — | Extra query parameters appended to the map URL. |
| `mapLocale` | `PMLocale?` | — | Forces the map language. Defaults to the host's `Accept-Language`. |
| `appStoreId` | `String?` | — | Numeric App Store ID used by the `app.review` command. |
| `coverImage` | `UIImage?` | — | Splash image shown until the web layer signals `web.ready`. |
| `userId` | `String?` | — | Opaque user id forwarded via `app.info`. |
| `secretKey` | `String?` | — | Shared secret forwarded via `app.info`. Treat as sensitive. |
| `offsetBottom` | `Int` | — | When `> 0`, the SDK reports the bottom safe-area inset as `0` (e.g. when the host adds its own bottom inset). |
| `launchURL` | `URL?` | — | URL captured from a Universal Link / Custom URL Scheme launch, replayed once `web.ready` fires. |
| `beaconUuid` | `String?` | — | Hyphenated iBeacon proximity UUID. Invalid UUIDs disable beacons silently. |
| `isWebViewInspectable` | `Bool` | — | Enables WebKit Inspector (`isInspectable`, iOS 16.4+). Off by default. |
| `delegate` | `PMMainViewControllerDelegate?` | — | Custom link-handling. |

### `pushLaunchURL(_:)`

Forwards a URL to the web app at runtime. Use this when the host receives a
Universal Link / Custom URL Scheme **after** `PMMainViewController` is
already on screen. URLs received before `web.ready` are stashed and
replayed automatically.

### `PMMainViewControllerDelegate`

```swift
@MainActor
protocol PMMainViewControllerDelegate: AnyObject {
    func openLink(_ url: URL, sharedCookie: Bool)
}
```

`sharedCookie == true` means the destination needs the current Platinumaps
session — open it in an in-app browser that shares cookies with the SDK's
WebView (`PMWebViewController` is provided for exactly this purpose).
`sharedCookie == false` means the link is safe to hand to
`SFSafariViewController` or the system browser.

The SDK already restricts the URL schemes it will forward to a conservative
allowlist (`http`, `https`, `tel`, `mailto`, `sms`, `geo`); anything else
is dropped before the delegate is called.

### `PMLocale`

Languages supported by the Platinumaps web layer:

```
ja, en, zh-cn, zh-tw, ko, fr, es, vi, id, my, th
```

### `PMWebViewController`

The in-app browser used for shared-cookie navigations. Set `pageUrl` before
presenting; the controller does not reload after the fact.

## Threading

`PMMainViewController` is implicitly main-actor isolated. All properties
must be set on the main thread; the delegate is also called on the main
actor. There is no need to hop queues from the host.

## What the SDK does NOT do

- It does not add navigation chrome — wrap the controller in your own
  `UINavigationController` if you want a close button.
- It does not request notification permissions, analytics consent, or any
  permission other than location, camera, microphone, and bluetooth.
- It does not retry network failures itself; the web layer surfaces its
  own retry UI.
