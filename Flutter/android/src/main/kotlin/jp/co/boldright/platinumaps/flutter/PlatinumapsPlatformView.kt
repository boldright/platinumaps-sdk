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
        val queryParams = args?.get("queryParams") as? Map<String, String>
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
        // `appStoreId`, and `locale` are not yet plumbed through to
        // the Android native SDK — the existing `PmMapOptions` does
        // not have first-class fields for them. Tracked as follow-up
        // work in `Flutter/DESIGN.md` §8.
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
