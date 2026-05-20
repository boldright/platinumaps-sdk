package jp.co.boldright.platinumaps.flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Entry point of the Platinumaps Flutter plugin on Android.
 *
 * The plugin registers a single PlatformView factory keyed by
 * `jp.co.boldright.platinumaps/map`. Activity-scoped lifecycle and
 * result callbacks (permissions, file chooser) are forwarded into the
 * underlying [jp.co.boldright.platinumaps.sdk.PmWebView] instances
 * automatically so that the host Flutter app does not need to wire
 * `onPause` / `onResume` / `onDestroy` / `onRequestPermissionsResult` /
 * `onActivityResult` manually — the inverse of the host-app
 * lifecycle contract that the bare native SDK requires
 * (see `CLAUDE.md` §Lifecycle contract).
 */
class PlatinumapsFlutterPlugin : FlutterPlugin, ActivityAware {

    companion object {
        const val VIEW_TYPE: String = "jp.co.boldright.platinumaps/map"
    }

    private var factory: PlatinumapsPlatformViewFactory? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val permissionsListener =
        ActivityPluginBinding.RequestPermissionsResultListener { requestCode, _, grantResults ->
            factory?.forwardPermissionResult(requestCode, grantResults)
            true
        }
    private val activityResultListener =
        io.flutter.plugin.common.PluginRegistry.ActivityResultListener { requestCode, resultCode, data ->
            factory?.forwardActivityResult(requestCode, resultCode, data)
            true
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
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(permissionsListener)
        activityBinding?.removeActivityResultListener(activityResultListener)
        activityBinding = null
        factory?.activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(permissionsListener)
        activityBinding?.removeActivityResultListener(activityResultListener)
        activityBinding = null
        factory?.activity = null
    }
}
