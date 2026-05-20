package jp.co.boldright.platinumaps.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Creates [PlatinumapsPlatformView] instances on demand and routes
 * activity-result / permission-result callbacks back to the currently
 * active views.
 */
internal class PlatinumapsPlatformViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    var activity: Activity? = null

    private val activeViews: MutableMap<Int, PlatinumapsPlatformView> = mutableMapOf()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        if (activity == null) {
            // In a normal `FlutterActivity` lifetime `activity` is set
            // by `onAttachedToActivity` before Flutter calls into this
            // factory, and the `context` Flutter passes in is the same
            // Activity. Engine-only or headless engine setups can
            // trigger this path; downstream permission requests need
            // a real Activity, so flag the fallback for diagnosis.
            Log.w(
                "PlatinumapsFlutter",
                "PlatformView created before onAttachedToActivity ran; " +
                    "permission prompts may not surface until the host attaches.",
            )
        }
        val view = PlatinumapsPlatformView(
            context = activity ?: context,
            messenger = messenger,
            viewId = viewId,
            args = params,
            onDispose = { id -> activeViews.remove(id) },
        )
        activeViews[viewId] = view
        return view
    }

    fun forwardPermissionResult(requestCode: Int, grantResults: IntArray) {
        // The native SDK matches its own request codes internally;
        // forward to every active view and let unrelated ones ignore.
        activeViews.values.forEach { it.handlePermissionResult(requestCode, grantResults) }
    }

    fun forwardActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        activeViews.values.forEach { it.handleActivityResult(requestCode, resultCode, data) }
    }

    fun forwardActivityResume() {
        activeViews.values.forEach { it.activityResume() }
    }

    fun forwardActivityPause() {
        activeViews.values.forEach { it.activityPause() }
    }

    fun forwardActivityDestroy() {
        activeViews.values.forEach { it.activityDestroy() }
    }
}
