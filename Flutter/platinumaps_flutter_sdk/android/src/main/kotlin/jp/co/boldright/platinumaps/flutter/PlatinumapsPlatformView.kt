package jp.co.boldright.platinumaps.flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import jp.co.boldright.platinumaps.sdk.PmMapBeaconOptions
import jp.co.boldright.platinumaps.sdk.PmMapOptions
import jp.co.boldright.platinumaps.sdk.PmWebView

/**
 * Hosts a [PmWebView] inside a Flutter PlatformView and bridges the
 * `onOpenLink` callback through a per-instance [MethodChannel].
 */
internal class PlatinumapsPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    private val viewId: Int,
    args: Map<String, Any?>?,
    private val onDispose: (Int) -> Unit,
) : PlatformView, PmWebView.OnOpenLinkListener {

    private val webView: PmWebView = PmWebView(context)
    private val methodChannel: MethodChannel = MethodChannel(
        messenger,
        "${PlatinumapsFlutterPlugin.VIEW_TYPE}/$viewId",
    )

    init {
        // Only claim the SDK's OnOpenLinkListener when the Dart side
        // actually has an `onOpenLink` callback. Leaving the listener
        // unset preserves the native SDK's default behaviour for the
        // browse.inapp (non-shared) command, which falls back to
        // CustomTabs. browse.app, map.navigate, and shared-cookie
        // browse.inapp links remain undelivered when no host
        // callback is wired — the native Android SDK has no internal
        // fallback for those code paths today.
        if (args?.get("hasOpenLinkHandler") as? Boolean == true) {
            webView.onOpenLinkListener = this
        }
        webView.openPlatinumaps(buildMapOptions(args))
    }

    companion object {
        /**
         * Translates the creation arguments the Dart side sends through
         * the platform channel into a [PmMapOptions] the native SDK
         * understands. Exposed at companion scope (rather than buried in
         * the `init` block) so unit tests can pin its behaviour without
         * standing up a real [PmWebView].
         *
         * `locale` is folded into the `culture` query parameter so the
         * Dart API reaches the Android web layer through the same path
         * the web app already understands. The native Android SDK has
         * no first-class `mapLocale` field today (CLAUDE.md notes that
         * Android derives culture from Accept-Language), but the web
         * app honours an explicit `culture=` override regardless of
         * platform.
         *
         * `offsetBottom`, `launchUrl`, `userId`, `secretKey`, and
         * `appStoreId` are accepted by the Dart API for forward
         * compatibility but the existing [PmMapOptions] does not
         * have first-class fields for them on Android. The Flutter
         * README documents the asymmetry.
         */
        internal fun buildMapOptions(args: Map<String, Any?>?): PmMapOptions {
            val mapSlug = (args?.get("mapSlug") as? String).orEmpty()
            // The Dart side declares `Map<String, String>?` for
            // queryParams, but the platform channel runtime erases the
            // generics: what arrives at the JVM is a `Map<*, *>` whose
            // values come back as `Any?`. Filter explicitly so a stray
            // non-String value cannot crash later inside
            // `appendQueryParameter`.
            val rawQueryParams: Map<String, String>? =
                (args?.get("queryParams") as? Map<*, *>)?.entries
                    ?.mapNotNull { (rawKey, rawValue) ->
                        val key = rawKey as? String ?: return@mapNotNull null
                        val value = rawValue as? String ?: return@mapNotNull null
                        key to value
                    }
                    ?.toMap()
            val locale = args?.get("locale") as? String
            val queryParams = when {
                locale == null -> rawQueryParams
                rawQueryParams == null -> mapOf("culture" to locale)
                else -> rawQueryParams + ("culture" to locale)
            }

            val beaconMap = (args?.get("beacon") as? Map<*, *>)?.let { raw ->
                raw.entries
                    .mapNotNull { (rawKey, rawValue) ->
                        val key = rawKey as? String ?: return@mapNotNull null
                        key to rawValue
                    }
                    .toMap()
            }
            val beaconOptions = beaconMap?.let {
                PmMapBeaconOptions(
                    uuid = (it["uuid"] as? String).orEmpty(),
                    minSample = (it["minSample"] as? Number)?.toInt(),
                    maxHistory = (it["maxHistory"] as? Number)?.toInt(),
                    memo = it["memo"] as? String,
                )
            }

            return PmMapOptions(
                mapPath = mapSlug,
                queryParams = queryParams,
                safeAreaTop = 0,
                safeAreaBottom = 0,
                beacon = beaconOptions,
            )
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        webView.onOpenLinkListener = null
        webView.activityDestroy()
        onDispose(viewId)
    }

    /**
     * Forwards Activity `onResume` from the plugin's lifecycle
     * observer. Resume is driven by the host Activity going to the
     * foreground, not by the PlatformView attaching to the Flutter
     * view hierarchy — those events do not coincide.
     */
    fun activityResume() {
        webView.activityResume()
    }

    /**
     * Forwards Activity `onPause` from the plugin's lifecycle
     * observer. Without this, GPS and BLE scanning continue while
     * the app sits in the background.
     */
    fun activityPause() {
        webView.activityPause()
    }

    /**
     * Forwards Activity `onDestroy`. `dispose()` already calls
     * `activityDestroy()` on its own, but the host Activity can go
     * away while the PlatformView is still attached, in which case
     * the lifecycle event arrives first.
     */
    fun activityDestroy() {
        webView.activityDestroy()
    }

    override fun onOpenLink(url: Uri, sharedCookie: Boolean) {
        methodChannel.invokeMethod(
            "onOpenLink",
            mapOf(
                "url" to url.toString(),
                "sharedCookie" to sharedCookie,
            ),
        )
    }

    fun handlePermissionResult(requestCode: Int, grantResults: IntArray) {
        webView.handlePermissionResult(requestCode, grantResults)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        webView.handleFileChooserResult(requestCode, resultCode, data)
    }
}
