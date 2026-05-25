package jp.co.boldright.platinumaps.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
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

    // `dispose()` and the host Lifecycle's onDestroy both reach the
    // native SDK's `activityDestroy()` (CLAUDE.md: "call exactly once
    // per WebView instance"). Either may fire first, so this flag
    // makes the second call a no-op.
    private var hasDestroyedWebView = false

    init {
        // Always claim the listener. The Dart side decides per-call
        // whether to handle the link or return 'fallback' to delegate
        // back to PmWebView's built-in routing.
        webView.onOpenLinkListener = this
        methodChannel.setMethodCallHandler { call, result -> handle(call, result) }

        val offsetBottom = (args?.get("offsetBottom") as? Number)?.toInt() ?: 0
        val (safeAreaTop, safeAreaBottom) = resolveSafeAreaInsets(
            context = context,
            zeroBottom = offsetBottom > 0,
        )
        webView.openPlatinumaps(
            buildMapOptions(
                args = args,
                safeAreaTop = safeAreaTop,
                safeAreaBottom = safeAreaBottom,
            ),
        )

        // The native Android SDK's `PmMapOptions` has no `launchUrl`
        // field today, so we can't fold this into `buildMapOptions`.
        // Push it through `pushLaunchURL` instead — the WebView is
        // still booting, so `PmWebView` stashes the URL and replays
        // it when `web.ready` arrives, matching the iOS path.
        val launchUrl = args?.get("launchUrl") as? String
        if (launchUrl != null) {
            val uri = Uri.parse(launchUrl)
            if (isAllowedLaunchUrlScheme(uri.scheme)) {
                webView.pushLaunchURL(uri)
            }
        }
    }

    /** Dart → native invocations coming from `PlatinumapsMapController`. */
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pushLaunchUrl" -> {
                val urlString = call.argument<String>("url")
                if (urlString == null) {
                    result.error("invalid_arguments", "pushLaunchUrl requires a `url`", null)
                    return
                }
                val uri = Uri.parse(urlString)
                if (!isAllowedLaunchUrlScheme(uri.scheme)) {
                    result.error(
                        "invalid_arguments",
                        "pushLaunchUrl requires a `url` with an allowlisted scheme",
                        null,
                    )
                    return
                }
                webView.pushLaunchURL(uri)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        /**
         * URL schemes the plugin will forward to
         * `PmWebView.pushLaunchURL`. Matches the native SDK's
         * `browseAllowedSchemes` and the iOS plugin glue's allowlist.
         */
        private val allowedLaunchUrlSchemes: Set<String> = setOf(
            "http", "https", "tel", "mailto", "sms", "geo",
        )

        /**
         * `true` when [scheme] is in the launch-URL allowlist. Pulled
         * out of `handle()` so unit tests can exercise the allowlist
         * without standing up a real WebView. Takes a `String?`
         * (rather than `Uri`) so the test source set can call it
         * without depending on Robolectric for `Uri.parse`.
         */
        internal fun isAllowedLaunchUrlScheme(scheme: String?): Boolean {
            if (scheme == null) return false
            return scheme.lowercase() in allowedLaunchUrlSchemes
        }

        /**
         * Resolves the system-bar + display-cutout insets from the host
         * Activity's decor view, so the WebView can lay out under
         * status bar / nav bar / notch the same way the iOS path does.
         * `zeroBottom` reflects the Dart-side `offsetBottom` flag: when
         * the host already draws a bottom inset (e.g. a tab bar) the
         * map should ignore the system one.
         */
        internal fun resolveSafeAreaInsets(
            context: Context,
            zeroBottom: Boolean,
        ): Pair<Int, Int> {
            val activity = context as? Activity ?: return Pair(0, 0)
            val rootInsets = ViewCompat.getRootWindowInsets(activity.window.decorView)
                ?: return Pair(0, 0)
            val systemInsets = rootInsets.getInsets(
                WindowInsetsCompat.Type.systemBars()
                    or WindowInsetsCompat.Type.displayCutout(),
            )
            return Pair(systemInsets.top, if (zeroBottom) 0 else systemInsets.bottom)
        }

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
         * `launchUrl`, `appStoreId`, and `offsetBottom` (the flag-only
         * value) are consumed by the init block, not here. Safe-area
         * insets are resolved by the caller and passed in.
         */
        internal fun buildMapOptions(
            args: Map<String, Any?>?,
            safeAreaTop: Int = 0,
            safeAreaBottom: Int = 0,
        ): PmMapOptions {
            val mapSlug = (args?.get("mapSlug") as? String).orEmpty()
            if (mapSlug.isEmpty()) {
                Log.w(
                    "PlatinumapsFlutter",
                    "mapSlug is empty; the WebView will load /maps/ and 404.",
                )
            }
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
                safeAreaTop = safeAreaTop,
                safeAreaBottom = safeAreaBottom,
                beacon = beaconOptions,
                userId = args?.get("userId") as? String,
                secretKey = args?.get("secretKey") as? String,
            )
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        webView.onOpenLinkListener = null
        destroyWebViewOnce()
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
     * the lifecycle event arrives first. The guard inside
     * [destroyWebViewOnce] keeps the second call a no-op.
     */
    fun activityDestroy() {
        destroyWebViewOnce()
    }

    private fun destroyWebViewOnce() {
        if (hasDestroyedWebView) return
        hasDestroyedWebView = true
        webView.activityDestroy()
    }

    override fun onOpenLink(url: Uri, sharedCookie: Boolean) {
        onOpenLink(url, sharedCookie, openInExternalApp = false)
    }

    override fun onOpenLink(url: Uri, sharedCookie: Boolean, openInExternalApp: Boolean) {
        methodChannel.invokeMethod(
            "onOpenLink",
            mapOf(
                "url" to url.toString(),
                "sharedCookie" to sharedCookie,
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == "fallback") {
                        webView.openLinkUsingDefault(url, sharedCookie, openInExternalApp)
                    }
                }
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            },
        )
    }

    fun handlePermissionResult(requestCode: Int, grantResults: IntArray) {
        webView.handlePermissionResult(requestCode, grantResults)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        webView.handleFileChooserResult(requestCode, resultCode, data)
    }
}
