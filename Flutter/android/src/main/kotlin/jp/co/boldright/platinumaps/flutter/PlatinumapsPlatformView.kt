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
        webView.onOpenLinkListener = this

        val mapSlug = (args?.get("mapSlug") as? String).orEmpty()
        @Suppress("UNCHECKED_CAST")
        val rawQueryParams = args?.get("queryParams") as? Map<String, String>
        val locale = args?.get("locale") as? String
        // `locale` is folded into the `culture` query parameter so the
        // Dart API reaches the Android web layer through the same path
        // the web app already understands. The native Android SDK has
        // no first-class `mapLocale` field today (CLAUDE.md notes that
        // Android derives culture from Accept-Language), but the web
        // app honours an explicit `culture=` override regardless of
        // platform.
        val queryParams = when {
            locale == null -> rawQueryParams
            rawQueryParams == null -> mapOf("culture" to locale)
            else -> rawQueryParams + ("culture" to locale)
        }

        @Suppress("UNCHECKED_CAST")
        val beaconMap = args?.get("beacon") as? Map<String, Any?>
        val beaconOptions = beaconMap?.let {
            PmMapBeaconOptions(
                uuid = (it["uuid"] as? String).orEmpty(),
                minSample = (it["minSample"] as? Number)?.toInt(),
                maxHistory = (it["maxHistory"] as? Number)?.toInt(),
                memo = it["memo"] as? String,
            )
        }

        // `offsetBottom`, `launchUrl`, `userId`, `secretKey`,
        // `appStoreId`, and `coverImage` are accepted by the Dart API
        // for forward compatibility but the existing `PmMapOptions`
        // does not have first-class fields for them on Android. The
        // README documents the asymmetry and DESIGN.md §8 #5 tracks
        // the parity backlog.
        val options = PmMapOptions(
            mapPath = mapSlug,
            queryParams = queryParams,
            safeAreaTop = 0,
            safeAreaBottom = 0,
            beacon = beaconOptions,
        )
        webView.openPlatinumaps(options)
    }

    override fun getView(): View = webView

    override fun onFlutterViewAttached(flutterView: View) {
        webView.activityResume()
    }

    override fun onFlutterViewDetached() {
        webView.activityPause()
    }

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        webView.onOpenLinkListener = null
        webView.activityDestroy()
        onDispose(viewId)
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
