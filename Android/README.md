# Platinumaps Android Integration Guide

This document explains how to integrate the Platinumaps SDK into an Android
application.

---

## Directory structure

```
Android/
├── README.md                       ← this file
├── platinumaps-sdk-release.aar     ← prebuilt library
├── platinumaps-sdk/                ← SDK module sources
└── sample/                         ← runnable sample app
```

## Requirements

- AGP 8.12+, Kotlin 1.8.22+, JDK 17.
- `minSdk 24`, `compileSdk` / `targetSdk 36`.
- Google Play Services Location 21.x (declared as a transitive dependency
  of the SDK).

## Required manifest entries

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

<!-- Only if you enable iBeacon ranging -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
```

Setting `android:required="false"` on the camera features lets the app
install on devices without camera hardware.

---

## Integration

### 1. Add the SDK

Either consume the prebuilt artifact:

```gradle
dependencies {
    implementation files("libs/platinumaps-sdk-release.aar")
}
```

…or include the source module from `Android/platinumaps-sdk/`:

```gradle
// settings.gradle
include ':platinumaps-sdk'
project(':platinumaps-sdk').projectDir = file('../platinumaps-sdk')

// app/build.gradle
dependencies {
    implementation project(':platinumaps-sdk')
}
```

### 2. Add `PmWebView` to your layout

```xml
<jp.co.boldright.platinumaps.sdk.PmWebView
    android:id="@+id/pm_sdk_web_view"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:focusable="true"
    android:focusableInTouchMode="true" />
```

### 3. Wire it up in your Activity

```kotlin
class WebViewActivity : AppCompatActivity(), PmWebView.OnOpenLinkListener {

    private lateinit var webView: PmWebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_web_view)
        webView = findViewById(R.id.pm_sdk_web_view)
        webView.onOpenLinkListener = this

        webView.openPlatinumaps(
            PmMapOptions(
                mapPath = "demo",
                queryParams = mapOf("key1" to "valueA", "key2" to "value2"),
                safeAreaTop = 0,
                safeAreaBottom = 0,
                beacon = PmMapBeaconOptions(
                    uuid = "B9407F30-F5F8-466E-AFF9-25556B57FE6D",
                    minSample = 5,
                    maxHistory = 5,
                    memo = "Smoke test",
                )
            )
        )

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.web_view_main)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }
    }

    // -- Lifecycle contract --------------------------------------------------

    override fun onPause()   { webView.activityPause();  super.onPause() }
    override fun onResume()  { super.onResume();         webView.activityResume() }
    override fun onDestroy() { webView.activityDestroy(); super.onDestroy() }

    // -- Permission / file chooser plumbing ---------------------------------

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        webView.handlePermissionResult(requestCode, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PmWebView.FILE_CHOOSER_REQUEST_CODE) {
            webView.handleFileChooserResult(requestCode, resultCode, data)
        }
    }

    // -- Outbound link handling ---------------------------------------------

    override fun onOpenLink(url: Uri, sharedCookie: Boolean) {
        if (sharedCookie) {
            // The destination needs the current Platinumaps session — open
            // an in-app browser that shares cookies with PmWebView.
            startActivity(
                Intent(this, WebBrowserActivity::class.java)
                    .putExtra(WebBrowserActivity.BROWSING_URL, url.toString())
            )
            return
        }
        // Anything else is safe to hand off to the system.
        startActivity(
            Intent(Intent.ACTION_VIEW, url)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
```

---

## Public API

### `PmWebView`

| Member | Description |
|--------|-------------|
| `openPlatinumaps(options: PmMapOptions)` | Loads the configured map. |
| `openPlatinumaps(pagePath, mapQuery, safeAreaTop, safeAreaBottom)` | Back-compat overload that takes a raw `key=value&...` string. |
| `activityPause()` | Pauses location, beacon, and heading sensors. Call from `onPause()`. |
| `activityResume()` | Resumes whatever was paused. Call from `onResume()`. |
| `activityDestroy()` | Tears down the WebView and releases native resources. Call from `onDestroy()`. |
| `handlePermissionResult(requestCode, grantResults)` | Forwards `onRequestPermissionsResult` results into the SDK. |
| `handleFileChooserResult(requestCode, resultCode, data)` | Forwards `onActivityResult` results for the file chooser. |
| `onOpenLinkListener: OnOpenLinkListener?` | Optional. Custom outbound link handling. |

### `PmMapOptions`

```kotlin
data class PmMapOptions(
    val mapPath: String,                      // e.g. "demo" or "demo/sr999"
    val queryParams: Map<String, String>? = null,
    val safeAreaTop: Int = 0,
    val safeAreaBottom: Int = 0,
    val beacon: PmMapBeaconOptions? = null,
)
```

### `PmMapBeaconOptions`

```kotlin
data class PmMapBeaconOptions(
    val uuid: String,                         // iBeacon proximity UUID, hyphenated
    val minSample: Int? = null,
    val maxHistory: Int? = null,
    val memo: String? = null,
)
```

The UUID is validated up front; an unparseable UUID silently disables
beacons rather than starting a wide-open BLE scan.

### `PmWebView.OnOpenLinkListener`

```kotlin
interface OnOpenLinkListener {
    fun onOpenLink(url: Uri, sharedCookie: Boolean)
}
```

`sharedCookie == true` indicates the link needs the current Platinumaps
session (typical example: stamp-rally reward downloads). The SDK already
restricts forwarded URL schemes to `{ http, https, tel, mailto, sms, geo }`;
the host does not need to filter again.

This v1 listener receives `browse.app`, `browse.inapp` with
`sharedCookie=true`, and `map.navigate` events. **It does not receive
`browse.inapp` with `sharedCookie=false`** — those URLs are handed to
Chrome Custom Tabs by the SDK itself, preserving the behaviour the
example above relies on (a `sharedCookie=false` callback always implies
the host should launch the URL in an external app).

### `PmWebView.OnOpenLinkRoutingListener`

```kotlin
interface OnOpenLinkRoutingListener : OnOpenLinkListener {
    fun onOpenLink(url: Uri, sharedCookie: Boolean, openInExternalApp: Boolean)
}
```

Opt-in variant for hosts that need to route every `browse.*` /
`map.navigate` event themselves — including `browse.inapp` with
`sharedCookie=false`, which the v1 listener never sees. Implementers
take over the SDK's built-in Chrome Custom Tabs launcher for those
URLs.

`openInExternalApp` is `true` for `browse.app` and `map.navigate` (the
web layer is signalling that the URL should leave the app) and `false`
for `browse.inapp` (the web layer wants the URL to open inside the
app). This is the canonical signal the v1 2-arg signature could not
express, since `browse.app` and `browse.inapp + sharedCookie=false`
both surfaced as `sharedCookie=false` callbacks.

The Flutter Android plugin implements this interface so the Dart-side
`onOpenLink` callback receives every event symmetrically with iOS;
native Android hosts that need the same level of control can adopt it
too. Hosts that are happy with the v1 routing should keep implementing
`OnOpenLinkListener` and require no changes.

Kotlin implementers only need to override the 3-argument `onOpenLink`
— the inherited 2-argument variant has a forwarding default the SDK
never calls. Java implementers must override both methods because
Kotlin's default interface methods are not visible to Java under the
default `-Xjvm-default=disable` mode.

---

## Android 16 (API level 36) host-application notes

The SDK is built and tested against `targetSdk 36`. When the host
application also targets API level 36, please be aware of these platform
behavior changes — the SDK itself does not require any code changes, but
the host is responsible for handling them:

- **Edge-to-edge enforcement.** Apps targeting API 36 cannot opt out of
  edge-to-edge display. Apply window insets to the layout that contains
  `PmWebView` (the snippet above does this with
  `ViewCompat.setOnApplyWindowInsetsListener`) so the map UI is not
  obscured by system bars.
- **Predictive back gesture.** If the host overrides `onBackPressed()`,
  migrate to `OnBackPressedCallback`. The SDK does not consume back events.
- **Large-screen orientation / resize constraints.** On displays with
  smallest width ≥ 600dp, `screenOrientation`, `resizeableActivity=false`,
  and aspect-ratio limits are ignored. Verify the layout that hosts
  `PmWebView` on tablets and foldables.

---

## What the SDK does NOT do

- It does not add navigation chrome — wrap the WebView in your own layout.
- It does not call `Activity#requestPermissions` directly: it goes through
  the standard `ActivityCompat` flow so the host's permission rationale
  / education UI keeps working.
- It does not use `WebView.addJavascriptInterface` — the bridge is one-way
  `evaluateJavascript`, avoiding the historical reflection attack surface.
