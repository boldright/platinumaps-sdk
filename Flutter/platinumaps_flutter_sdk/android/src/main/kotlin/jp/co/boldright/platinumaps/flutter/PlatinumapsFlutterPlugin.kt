package jp.co.boldright.platinumaps.flutter

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import jp.co.boldright.platinumaps.sdk.PmWebView

/**
 * Entry point of the Platinumaps Flutter plugin on Android.
 *
 * The plugin registers a single PlatformView factory keyed by
 * `jp.co.boldright.platinumaps/map`. Two pieces of activity-scoped
 * plumbing are wired automatically so the host Flutter app needs no
 * extra code:
 *
 *  * **Activity lifecycle.** A `DefaultLifecycleObserver` is attached
 *    to the host Activity's `Lifecycle` so that `onPause` / `onResume`
 *    / `onDestroy` drive `PmWebView.activityPause/Resume/Destroy` on
 *    every active map view. Without this, location and BLE scanning
 *    would keep running when the user backgrounds the app — a
 *    Play-Store-policy violation and a battery drain.
 *  * **Permission and activity results.** Listeners route the SDK's
 *    own request codes back into the active views; results for any
 *    other request code are deliberately not claimed so that other
 *    plugins on the same Activity continue to receive their own
 *    callbacks.
 */
class PlatinumapsFlutterPlugin : FlutterPlugin, ActivityAware {

    companion object {
        const val VIEW_TYPE: String = "jp.co.boldright.platinumaps/map"

        // The set of request codes the native Android SDK issues. The
        // plugin's result listeners only claim the result (i.e., return
        // `true` to `PluginRegistry`) for codes in these sets, so other
        // plugins on the same Activity continue to receive their own
        // results.
        private val SDK_PERMISSION_REQUEST_CODES: Set<Int> = setOf(
            PmWebView.PERMISSION_REQUEST_CODE,
            PmWebView.REQUEST_CODE_PERMISSIONS_LOCATION,
            PmWebView.REQUEST_CODE_PERMISSIONS_BEACON,
        )

        private val SDK_ACTIVITY_RESULT_REQUEST_CODES: Set<Int> = setOf(
            PmWebView.FILE_CHOOSER_REQUEST_CODE,
        )
    }

    private var factory: PlatinumapsPlatformViewFactory? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var lifecycle: Lifecycle? = null

    private val permissionsListener =
        io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener { requestCode, _, grantResults ->
            if (requestCode in SDK_PERMISSION_REQUEST_CODES) {
                factory?.forwardPermissionResult(requestCode, grantResults)
                true
            } else {
                false
            }
        }
    private val activityResultListener =
        io.flutter.plugin.common.PluginRegistry.ActivityResultListener { requestCode, resultCode, data ->
            if (requestCode in SDK_ACTIVITY_RESULT_REQUEST_CODES) {
                factory?.forwardActivityResult(requestCode, resultCode, data)
                true
            } else {
                false
            }
        }

    private val lifecycleObserver = object : DefaultLifecycleObserver {
        override fun onResume(owner: LifecycleOwner) {
            factory?.forwardActivityResume()
        }
        override fun onPause(owner: LifecycleOwner) {
            factory?.forwardActivityPause()
        }
        override fun onDestroy(owner: LifecycleOwner) {
            factory?.forwardActivityDestroy()
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val f = PlatinumapsPlatformViewFactory(binding.binaryMessenger)
        factory = f
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, f)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        factory = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        factory?.activity = binding.activity
        binding.addRequestPermissionsResultListener(permissionsListener)
        binding.addActivityResultListener(activityResultListener)

        // `ActivityPluginBinding.lifecycle` returns Flutter's
        // `HiddenLifecycleReference`, which wraps the host Activity's
        // androidx.lifecycle.Lifecycle. The `FlutterLifecycleAdapter`
        // helper isn't shipped in the current Flutter Android engine
        // artifact (only `HiddenLifecycleReference.class` is present
        // under `io/flutter/embedding/engine/plugins/lifecycle/`), so
        // we unwrap the reference directly here.
        val lc = (binding.lifecycle as HiddenLifecycleReference).lifecycle
        lc.addObserver(lifecycleObserver)
        lifecycle = lc
    }

    override fun onDetachedFromActivityForConfigChanges() {
        teardownActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        teardownActivity()
    }

    private fun teardownActivity() {
        lifecycle?.removeObserver(lifecycleObserver)
        lifecycle = null
        activityBinding?.removeRequestPermissionsResultListener(permissionsListener)
        activityBinding?.removeActivityResultListener(activityResultListener)
        activityBinding = null
        factory?.activity = null
    }
}
