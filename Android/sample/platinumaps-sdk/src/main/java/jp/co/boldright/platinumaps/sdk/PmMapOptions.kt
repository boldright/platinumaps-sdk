package jp.co.boldright.platinumaps.sdk

/**
 * Configuration used by [PmWebView.openPlatinumaps] when loading a map.
 *
 * @property mapPath Path of the map to display (e.g. "demo" or "demo/sr999").
 * Appended to the base URL "https://platinumaps.jp/maps/".
 * @property queryParams Optional extra query parameters merged into the map URL.
 * @property safeAreaTop Height of the top safe area (status bar / notch) in
 * pixels. Forwarded to the web layer so it can lay out under system bars.
 * Defaults to `0`.
 * @property safeAreaBottom Height of the bottom safe area (navigation bar) in
 * pixels. Forwarded to the web layer. Defaults to `0`.
 * @property beacon Beacon configuration. Pass `null` to disable beacon
 * scanning entirely.
 * @property userId Opaque user identifier the web app may consume via the
 * `app.info` command. Defaults to `null`.
 * @property secretKey Opaque shared secret the web app may consume via the
 * `app.info` command. Defaults to `null`.
 */
data class PmMapOptions(
    val mapPath: String,
    val queryParams: Map<String, String>? = null,
    val safeAreaTop: Int = 0,
    val safeAreaBottom: Int = 0,
    val beacon: PmMapBeaconOptions? = null,
    val userId: String? = null,
    val secretKey: String? = null,
)

/**
 * Beacon settings nested inside [PmMapOptions].
 *
 * @property uuid Proximity UUID of the beacons to listen for. The string
 * must parse as a [java.util.UUID]; otherwise beacons are disabled.
 * @property minSample Optional. Number of RSSI samples the map should
 * average before reacting; falls back to the map-side default when `null`.
 * @property maxHistory Optional. Maximum history length the map should
 * retain; falls back to the map-side default when `null`.
 * @property memo Optional. Free-form string forwarded to the map for
 * diagnostic / debugging purposes.
 */
data class PmMapBeaconOptions(
    val uuid: String,
    val minSample: Int? = null,
    val maxHistory: Int? = null,
    val memo: String? = null
)
