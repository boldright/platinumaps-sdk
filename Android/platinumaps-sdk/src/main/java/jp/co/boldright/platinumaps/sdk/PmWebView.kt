package jp.co.boldright.platinumaps.sdk

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Context.BLUETOOTH_SERVICE
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.JsResult
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AlertDialog
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONObject
import java.lang.StringBuilder
import java.util.Date
import java.util.UUID

/**
 * The Platinumaps `WebView` that hosts the Platinum Maps web app and bridges
 * the limited set of native capabilities it consumes — geolocation,
 * heading, iBeacon ranging, in-app browser, file chooser, app-store review
 * — over a `command://` URL scheme.
 *
 * **Bridge protocol**
 *
 * * Web → native: `command://<name>?requestId=<id>&...` is intercepted in
 *   `shouldOverrideUrlLoading`, the navigation is cancelled, and the
 *   command is dispatched by `runCommand`.
 * * Native → web: replies are sent via
 *   `commandCallback('<name>','<requestId>',<argsJSON>)`. Both the command
 *   name and the request id are JSON-encoded so an attacker-influenced
 *   request id cannot break out of the JavaScript string context.
 *
 * **Lifecycle contract**
 *
 * The host Activity (or Fragment) must forward four callbacks:
 *
 * * `activityPause()` from `onPause` — stops location/beacon/sensor work.
 * * `activityResume()` from `onResume` — restores whatever was running.
 * * `activityDestroy()` from `onDestroy` — releases all native resources.
 * * `handlePermissionResult` and `handleFileChooserResult` from their
 *   respective callbacks.
 *
 * **Threading**
 *
 * All public methods and all internal mutable state (location lists, beacon
 * buffer, heading callbacks) are expected to be touched only from the main
 * looper. BLE scan results, which arrive on a binder thread, are bounced
 * onto the main looper before they touch shared state.
 */
class PmWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : WebView(context, attrs, defStyleAttr) {
    private enum class PMCommand(val rawValue: String) {
        WEB_READY("web.ready"),
        WEB_WILL_RELOAD("web.willreload"),
        LOCATION_STATUS("location.status"),
        LOCATION_AUTHORIZE("location.authorize"),
        LOCATION_ONCE("location.once"),
        LOCATION_WATCH("location.watch"),
        LOCATION_CLEAR_WATCH("location.clearwatch"),

        BROWSE_APP("browse.app"),
        BROWSE_IN_APP("browse.inapp"),
        APP_INFO("app.info"),
        APP_DETECT("app.detect"),
        APP_REVIEW("app.review"),
        MAP_NAVIGATE("map.navigate"),

        WEB_FILE_CHOOSER("web.filechooser"),

        //region Beacon
        BEACON_AUTHORIZE("beacon.authorize"),
        BEACON_ONCE("beacon.once"),
        BEACON_WATCH("beacon.watch"),
        BEACON_CLEAR_WATCH("beacon.clearwatch"),
        //endregion

        //region Heading
        HEADING_WATCH("heading.watch"),
        HEADING_CLEAR_WATCH("heading.clearwatch")
        //endregion
    }

    enum class PmLocationAuthorizationStatus(val rawValue: String) {
        NOT_DETERMINED("notDetermined"),
        AUTHORIZED("authorized"),
        DENIED("denied"),
    }

    private val TAG = "platinumap.webview"
    private val TAG_BEACON = "platinumaps.beacon"
    private val TAG_HEADING = "platinumaps.heading"
    private val TAG_RETRY = "platinumaps.retry"

    private var originalUrl: Uri? = null

    // True while the WebView is loading a top-level page.
    private var isWebViewLoading = false

    // Timestamp captured at the start of the most recent WebView load —
    // retained for future timeout / telemetry use.
    private var webViewLoadingAt: Date? = null

    // True once the web layer has signalled `web.ready` at least once.
    private var hasWebReady = false

    /** Number of failed initial-load attempts since the last `web.ready`,
     * `web.willreload`, or background reset. Drives the exponential
     * backoff in [scheduleNextRetry]. */
    private var retryAttempt: Int = 0

    /** True once the initial load has failed at least once and not yet
     * succeeded. Survives the background-reset path so [activityResume]
     * can tell "user is staring at a stuck splash" apart from "load is
     * still in flight" and fire an immediate retry only in the former
     * case. Cleared on `web.ready` and `web.willreload`. */
    private var hasInitialLoadFailed: Boolean = false

    /** Pending retry callback, or null if no retry is currently
     * scheduled. Held so we can cancel it via
     * [Handler.removeCallbacks] when the load succeeds, the host
     * activity pauses, or the view is destroyed. */
    private var pendingRetryRunnable: Runnable? = null

    private var isMeasuringLocation = false
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var lastLocation: Location? = null

    /** Receive location updates even if the location has not changed */
    private val minUpdateDistanceMeters = 0F

    /** Minimum update interval for location information in milliseconds */
    private val minUpdateIntervalMillis = 320L

    /** Maximum update interval for location information in milliseconds */
    private val maxUpdateIntervalMillis = 1000L

    private var locationAuthorizeRequestId: String? = null
    private var locationOnceRequestIds = mutableListOf<String>()
    private var locationWatchRequestIds = mutableListOf<String>()

    /**
     * Callback to receive location updates from FusedLocationProviderClient.
     * Always dispatched on the main looper (configured at
     * `requestLocationUpdates`).
     */
    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(locationResult: LocationResult) {
            locationResult.lastLocation?.let { location ->
                this@PmWebView.lastLocation = location
                updateLocation(location, false)
            }
        }
    }

    //region Beacon

    private var beaconListeningUuid: String? = null

    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var isScanningBle = false
    private var isScanningBlePaused = false

    /** Request ID for beacon.authorize */
    private var beaconAuthorizeRequestId: String? = null

    /** Request IDs for beacon.once */
    private var beaconOnceRequestIds = mutableListOf<String>()

    /** Request IDs for beacon.watch */
    private var beaconWatchRequestIds = mutableListOf<String>()

    /**
     * Beacons are received one by one from the BLE scanner, but they are
     * sent to the web in batches.
     *
     * Thread-safety: every mutation of `beaconBuffer` must happen on the
     * main looper. `onScanResult` therefore re-posts the buffer mutation;
     * `flushBeaconBuffer` is itself only ever invoked from main.
     */
    private val beaconBuffer = mutableListOf<PmBeaconDto>()

    /** The time window in milliseconds for buffering beacon data before sending it to the web. */
    private val beaconBufferingWindow: Long = 500

    /** The last time beacon information (or error information) was sent to the web. */
    private var lastBeaconUpdateTime: Date = Date()

    /** True if a buffer flush is scheduled */
    private var isBeaconBufferFlushReserved = false

    /** Lazily-cached handler bound to the main looper. */
    private val mainHandler = Handler(Looper.getMainLooper())

    //endregion

    //region Heading

    /** Sensor listener required for heading calculation. */
    private var sensorHeadingListener: SensorEventListener? = null

    /** The last known magnetic heading (integer value). */
    private var lastMagneticHeading: Int? = null

    /** The last time the heading was notified. */
    private var lastMagneticHeadingNotifiedAt: Date = Date()

    /** The interval in milliseconds for pushing heading updates to the web. */
    private val magneticHeadingPushInterval = 100L

    /** Request IDs for heading.watch */
    private val headingRequestIds = mutableListOf<String>()

    //endregion

    private val parentActivity: Activity?
        get() {
            return context as? Activity
        }

    private var playStoreId: String? = null
    private var appLinkUri: Uri? = null
    private var userId: String? = null
    private var secretKey: String? = null

    /** Delegate that the host may set to take over outbound link handling. */
    var onOpenLinkListener: OnOpenLinkListener? = null

    // Temporarily holds permission request callbacks
    private var geolocationPermissionsCallback: GeolocationPermissions.Callback? = null
    private var geolocationOrigin: String? = null
    private var activePermissionRequest: PermissionRequest? = null
    private var filePathCallback: ValueCallback<Array<Uri>>? = null

    init {
        if (BuildConfig.DEBUG) {
            setWebContentsDebuggingEnabled(true)
        }

        // Enable JavaScript and DOM storage so the Platinumaps web app can run.
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.setGeolocationEnabled(true)
        settings.setSupportMultipleWindows(true)
        val userAgent = "${settings.userAgentString} Platinumaps/2.0.0"
        settings.userAgentString = userAgent
        // Intercept navigations so `command://...` can be dispatched.
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                isWebViewLoading = false
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                onError(request, error?.description?.toString())
                scheduleRetryIfInitialLoadFailed(request)
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?
            ) {
                super.onReceivedHttpError(view, request, errorResponse)
                onError(request, errorResponse?.reasonPhrase)
                scheduleRetryIfInitialLoadFailed(request)
            }

            private fun onError(request: WebResourceRequest?, message: String?) {
                val host = request?.url?.host
                if (host != null) {
                    Log.e(TAG, "error: url=${request.url} message=$message")
                } else {
                    Log.e(TAG, "error: message=$message")
                }
            }

            /**
             * Triggers the initial-load retry loop, but only for the
             * main frame and only before the web layer has signalled
             * `web.ready`. Subresource errors and post-ready navigation
             * failures are surfaced to the web layer, which decides
             * what to do with them.
             */
            private fun scheduleRetryIfInitialLoadFailed(
                request: WebResourceRequest?
            ) {
                if (request?.isForMainFrame == true && !hasWebReady) {
                    scheduleNextRetry()
                }
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                request?.url?.let { uri ->
                    // Called for both `window.open` and `<a>` taps. Since
                    // we never want WebKit to navigate away from
                    // platinumaps.jp, intercept and either dispatch a
                    // command, open in an in-app browser, or fall through.
                    if (openRequest(uri) == 0u) {
                        return true
                    }
                }
                return false
            }
        }

        webChromeClient = object : WebChromeClient() {
            override fun onJsAlert(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                // Surface the web app's `alert()` as a native dialog.
                AlertDialog.Builder(context)
                    .setMessage(message)
                    .setPositiveButton(android.R.string.ok) { dialog, which ->
                        result?.confirm()
                    }
                    .setCancelable(false)
                    .create()
                    .show()
                return true
            }

            override fun onJsConfirm(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                // Surface the web app's `confirm()` as a native dialog.
                AlertDialog.Builder(context)
                    .setMessage(message)
                    .setPositiveButton(android.R.string.ok) { dialog, which ->
                        result?.confirm()
                    }
                    .setNegativeButton(android.R.string.cancel) { dialog, which ->
                        result?.cancel()
                    }
                    .setCancelable(false)
                    .create()
                    .show()
                return true
            }

            // File picker handler — bridged through to the host Activity.
            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                // If a previous file chooser is still outstanding, cancel
                // it before replacing the callback.
                this@PmWebView.filePathCallback?.onReceiveValue(null)

                this@PmWebView.filePathCallback = filePathCallback

                val intent = fileChooserParams?.createIntent()
                intent?.let {
                    val activity = context as? Activity
                    if (activity != null) {
                        ActivityCompat.startActivityForResult(
                            activity,
                            it,
                            FILE_CHOOSER_REQUEST_CODE,
                            null
                        )
                    }
                }
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                if (request == null) {
                    super.onPermissionRequest(request)
                    return
                }

                val activity = context as? Activity
                if (activity == null) {
                    request.deny()
                    return
                }

                // Translate WebView permission requests into Android
                // runtime permissions.
                val requestedPermissions = mutableListOf<String>()

                if (request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) {
                    requestedPermissions.add(Manifest.permission.CAMERA)
                }
                if (request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) {
                    requestedPermissions.add(Manifest.permission.RECORD_AUDIO)
                }

                if (requestedPermissions.isNotEmpty()) {
                    val ungrantedPermissions = requestedPermissions.filter {
                        ContextCompat.checkSelfPermission(
                            activity,
                            it
                        ) != PackageManager.PERMISSION_GRANTED
                    }

                    if (ungrantedPermissions.isNotEmpty()) {
                        // Stash the request and wait for the result; we
                        // call `request.grant()` from
                        // `onRequestPermissionsResult`.
                        activePermissionRequest = request
                        ActivityCompat.requestPermissions(
                            activity,
                            ungrantedPermissions.toTypedArray(),
                            PERMISSION_REQUEST_CODE
                        )
                    } else {
                        request.grant(request.resources)
                    }
                } else {
                    // No permissions required → deny so the web side does
                    // not hang.
                    request.deny()
                }
            }

            override fun onGeolocationPermissionsShowPrompt(
                origin: String?,
                callback: GeolocationPermissions.Callback?
            ) {
                if (callback == null) {
                    return super.onGeolocationPermissionsShowPrompt(origin, callback)
                }

                val activity = context as? Activity
                if (activity == null) {
                    callback.invoke(origin, false, false)
                    return
                }

                geolocationPermissionsCallback = callback
                geolocationOrigin = origin

                val permission = Manifest.permission.ACCESS_FINE_LOCATION

                if (ContextCompat.checkSelfPermission(
                        activity,
                        permission
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(permission),
                        GEOLOCATION_PERMISSION_REQUEST_CODE
                    )
                } else {
                    // Already granted — invoke synchronously.
                    callback.invoke(origin, true, false)
                }
            }
        }

        // Cookies (including third-party) are required so authenticated
        // flows like stamp-rally rewards work across origins.
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptThirdPartyCookies(this, true)
        cookieManager.setAcceptCookie(true)
    }

    private fun openPlatinumaps(options: PmMapOptions, queryPrams: String?) {
        // Build the URL safely with Uri.Builder so query values are encoded
        // correctly even when they contain `&`, `=`, etc.
        val uriBuilder = "https://platinumaps.jp/maps/".toUri().buildUpon()

        // 1. Map path.
        uriBuilder.appendPath(options.mapPath)

        // 2. Native marker (the web app branches on this).
        uriBuilder.appendQueryParameter("native", "1")

        // 3a. Back-compat: a raw `key=value&...` string from the old API.
        queryPrams?.takeIf { it.isNotBlank() }?.let { query ->
            val queryItems = query.split('&')
            for (queryItem in queryItems) {
                // Split on the first `=` only; values may legitimately
                // contain `=`.
                val parts = queryItem.split('=', limit = 2)
                if (parts.size == 2 && parts[0].isNotEmpty()) {
                    uriBuilder.appendQueryParameter(parts[0], parts[1])
                }
            }
        }

        // 3b. Caller-supplied query params (`PmMapOptions.queryParams`).
        options.queryParams?.forEach { (key, value) ->
            uriBuilder.appendQueryParameter(key, value)
        }

        // 4. Safe-area insets so the web layer can lay out under system bars.
        uriBuilder.appendQueryParameter("safearea", "${options.safeAreaTop},${options.safeAreaBottom}")

        // 5. Beacon configuration.
        options.beacon?.let { beacon ->
            // Validate the UUID up front so we never start a scanner with
            // a junk filter (which would silently let every Apple-
            // manufacturer advertisement through).
            beaconListeningUuid = try {
                UUID.fromString(beacon.uuid)
                beacon.uuid
            } catch (ex: IllegalArgumentException) {
                Log.w(TAG_BEACON, "openPlatinumaps: invalid beacon uuid '${beacon.uuid}', beacons disabled")
                null
            }
            beacon.minSample?.let {
                uriBuilder.appendQueryParameter("beaconminsample", it.toString())
            }
            beacon.maxHistory?.let {
                uriBuilder.appendQueryParameter("beaconmaxhistory", it.toString())
            }
            beacon.memo?.let {
                uriBuilder.appendQueryParameter("memo", it)
            }
        }

        originalUrl = uriBuilder.build()
        loadWebView()
    }

    /**
     * Loads a Platinumaps map in the WebView using a configuration object.
     * This method constructs the full map URL from the provided options and loads it.
     *
     * @param options An instance of `PmMapOptions` containing all necessary configurations,
     * such as the map path, query parameters, safe area insets, and beacon settings.
     */
    fun openPlatinumaps(options: PmMapOptions) {
        openPlatinumaps(options, null)
    }

    /**
     * Displays the specified Platinumaps map.
     *
     * This function constructs a full URL from the provided page path, query parameters,
     * and device-specific safe area dimensions. It then loads this URL into the WebView.
     * This is an alternative to the `PmMapOptions`-based method.
     *
     * @param pagePath The URL path of the map to display, appended to the base URL "https://platinumaps.jp/maps/".
     * @param mapQuery Optional query parameters for the map, provided as a string (e.g., "key1=value1&key2=value2"). Can be `null`.
     * @param safeAreaTop The height of the top safe area (e.g., status bar or notch) in pixels.
     * @param safeAreaBottom The height of the bottom safe area (e.g., navigation bar) in pixels.
     */
    fun openPlatinumaps(
        pagePath: String,
        mapQuery: String?,
        safeAreaTop: Int,
        safeAreaBottom: Int
    ) {
        openPlatinumaps(PmMapOptions(pagePath, null, safeAreaTop, safeAreaBottom), mapQuery)
    }

    //region WebView

    private fun loadWebView() {
        originalUrl?.let {
            val loadingAt = Date()
            webViewLoadingAt = loadingAt

            loadUrl(it.toString())
            isWebViewLoading = true
        }
    }

    //endregion

    //region Initial Load Retry
    //
    // The SDK retries the initial map URL when it fails to load, because
    // there is no web-side retry UI for the document that hosts it: a
    // transient DNS hiccup, a 5xx from the origin, or the user briefly
    // losing connectivity would otherwise leave the splash screen on
    // indefinitely. The retry loop is intentionally narrow:
    //
    //   * Only the *initial* load is monitored. Once `web.ready` fires
    //     the web layer owns navigation and the SDK steps out of the way.
    //   * Retries continue forever while the host activity is in the
    //     foreground. The backoff caps at [maxRetryDelaySeconds], so the
    //     load is reattempted at most every few seconds.
    //   * `activityPause()` cancels any pending retry and resets the
    //     backoff so `activityResume()` feels like a fresh start.

    /** Cap on the wait between initial-load retries, in seconds. The
     * backoff is `min(2^attempt, maxRetryDelaySeconds)`, yielding the
     * sequence `1, 2, 4, 8, 8, 8, …`. A user staring at the splash will
     * not tolerate longer waits, and longer waits do not meaningfully
     * reduce origin load for a single client. */
    private val maxRetryDelaySeconds: Long = 8L

    /**
     * Schedules the next retry of the initial map URL with exponential
     * backoff. Any retry already in flight is replaced. The attempt
     * counter is advanced so successive failures wait longer up to
     * [maxRetryDelaySeconds]. Also latches [hasInitialLoadFailed],
     * which the foreground-recovery path consults after the counter has
     * been zeroed by [resetRetryState].
     */
    private fun scheduleNextRetry() {
        hasInitialLoadFailed = true
        val attempt = retryAttempt
        retryAttempt = attempt + 1
        val delayMillis = computeRetryDelayMillis(attempt)
        logRetry { "scheduleNextRetry: attempt=$attempt delay=${delayMillis}ms" }
        scheduleRetry(delayMillis)
    }

    /**
     * Schedules an immediate retry without advancing the backoff
     * counter. Used on `activityResume()` so the user sees one fresh
     * attempt before any backoff kicks in.
     */
    private fun scheduleImmediateRetry() {
        logRetry { "scheduleImmediateRetry" }
        scheduleRetry(0L)
    }

    private fun scheduleRetry(delayMillis: Long) {
        cancelPendingRetry()
        val runnable = Runnable {
            pendingRetryRunnable = null
            if (!hasWebReady) {
                logRetry { "firing retry: reloading initial URL" }
                loadWebView()
            }
        }
        pendingRetryRunnable = runnable
        if (delayMillis <= 0L) {
            mainHandler.post(runnable)
        } else {
            mainHandler.postDelayed(runnable, delayMillis)
        }
    }

    /**
     * Cancels any pending retry without touching the attempt counter, so
     * a subsequent [scheduleNextRetry] resumes the backoff where it left
     * off.
     */
    private fun cancelPendingRetry() {
        pendingRetryRunnable?.let {
            logRetry { "cancelPendingRetry" }
            mainHandler.removeCallbacks(it)
        }
        pendingRetryRunnable = null
    }

    /**
     * Cancels any pending retry and resets the attempt counter. The
     * [hasInitialLoadFailed] latch is only cleared by the success paths
     * (`web.ready`, `web.willreload`); see [clearInitialLoadFailureLatch].
     * Called on `web.ready`, on `web.willreload`, and on [activityPause].
     */
    private fun resetRetryState() {
        cancelPendingRetry()
        retryAttempt = 0
    }

    /**
     * Clears the [hasInitialLoadFailed] latch. Separated from
     * [resetRetryState] so the background path can wipe pending work
     * without telling foreground recovery that the load has succeeded.
     */
    private fun clearInitialLoadFailureLatch() {
        if (hasInitialLoadFailed) {
            logRetry { "clearInitialLoadFailureLatch: initial load now considered successful" }
        }
        hasInitialLoadFailed = false
    }

    /**
     * Emits a debug log only on debuggable builds, so retry diagnostics
     * never reach end-user `logcat` output. The message is built lazily
     * via the lambda so the string is not allocated in release builds.
     */
    private inline fun logRetry(messageBuilder: () -> String) {
        if (BuildConfig.DEBUG) {
            Log.d(TAG_RETRY, messageBuilder())
        }
    }

    /**
     * Returns the backoff delay for the given attempt index in
     * milliseconds. The cap is reached at attempt 3, so the result is
     * constant beyond that and we need not worry about left-shift
     * overflow for large attempt values.
     */
    private fun computeRetryDelayMillis(attempt: Int): Long {
        val seconds = if (attempt >= 30) {
            maxRetryDelaySeconds
        } else {
            (1L shl attempt).coerceAtMost(maxRetryDelaySeconds)
        }
        return seconds * 1000L
    }

    //endregion

    //region Command

    // Decide what to do with a URI the WebView is trying to navigate to.
    private fun openRequest(uri: Uri): UInt {
        if (uri.scheme == "command") {
            runCommand(uri)
        } else if (hasWebReady) {
            // Non-command URIs from the web app are handed to the in-app
            // browser. We wait until `web.ready` has fired so we don't
            // intercept the very first navigation that loads the map page
            // itself. `shouldOverrideUrlLoading` is also called on
            // redirects, which is another reason to gate on `hasWebReady`.
            // Apply the same scheme allowlist as the `browse.*` commands so
            // a compromised web layer cannot escalate via `<a href="intent://...">`
            // or other dangerous schemes that `CustomTabsIntent` would otherwise
            // forward to the system.
            if (!isSchemeAllowedForBrowse(uri)) {
                Log.w(TAG, "openRequest: blocked disallowed scheme '${uri.scheme}'")
                return 0u
            }
            openWebBrowseInApp(uri)
        } else {
            return 1u;
        }
        return 0u
    }

    private fun getCommand(commandUri: Uri): PMCommand? {
        commandUri.host?.let { command ->
            return PMCommand.values().firstOrNull { it.rawValue == command }
        }
        return null
    }

    private fun runCommand(commandUri: Uri): UInt {
        val command = getCommand(commandUri)
        command ?: return 1u
        val requestId = commandUri.getQueryParameter("requestId")
        requestId ?: return 1u
        when (command) {
            PMCommand.APP_INFO -> {
                val args = mutableMapOf<String, String>()
                userId?.let {
                    if (it.isNotEmpty()) {
                        args["userId"] = it
                    }
                }
                secretKey?.let {
                    if (it.isNotEmpty()) {
                        args["secretKey"] = it
                    }
                }
                commandCallback(command, requestId, args)
                return 0u
            }

            PMCommand.WEB_READY -> {
                hasWebReady = true
                // Successful initial load — drop any retry state that
                // may have accumulated from earlier failed attempts.
                resetRetryState()
                clearInitialLoadFailureLatch()
                val args = mutableMapOf<String, String>()
                appLinkUri?.let {
                    args["launchUrl"] = it.toString()
                }
                appLinkUri = null
                commandCallback(command, requestId, args)
                return 0u
            }

            PMCommand.WEB_WILL_RELOAD -> {
                hasWebReady = false
                // The web layer is dropping its document and re-loading.
                // Treat this like a fresh initial load: clear any retry
                // state so the backoff starts at zero if the upcoming
                // load fails.
                resetRetryState()
                clearInitialLoadFailureLatch()
                commandCallback(command, requestId, mapOf())
                return 0u
            }

            PMCommand.LOCATION_STATUS -> {
                val status = locationPermissionStatus()
                locationStatusCommandCallback(status, command, requestId)
                return 0u
            }

            PMCommand.LOCATION_AUTHORIZE -> {
                val status = locationPermissionStatus()
                if (status == PmLocationAuthorizationStatus.AUTHORIZED) {
                    locationStatusCommandCallback(status, command, requestId)
                } else {
                    locationAuthorizeRequestId = requestId
                    requestLocationPermission()
                }
                return 0u
            }

            PMCommand.LOCATION_ONCE -> {
                locationOnceRequestIds.add(requestId)
                startLocationRequest(command, requestId)
                return 0u
            }

            PMCommand.LOCATION_WATCH -> {
                locationWatchRequestIds.add(requestId)
                startLocationRequest(command, requestId)
                return 0u
            }

            PMCommand.LOCATION_CLEAR_WATCH -> {
                locationWatchRequestIds.clear()
                stopLocationRequestIfNoRequest()
            }

            PMCommand.BROWSE_APP, PMCommand.BROWSE_IN_APP -> {
                commandWebBrowse(command, commandUri)
            }

            PMCommand.MAP_NAVIGATE -> {
                commandWebBrowse(command, commandUri)
            }

            PMCommand.APP_DETECT -> {
            }

            PMCommand.APP_REVIEW -> {
                playStoreId?.let {
                    val playStoreUri = "https://play.google.com/store/apps/details?id=${it}"
                    playStoreUri.toUri().let {
                        openWebBrowseApp(it)
                    }
                }
            }

            PMCommand.WEB_FILE_CHOOSER -> {
            }

            //region Beacon
            PMCommand.BEACON_AUTHORIZE -> {
                parentActivity?.let {
                    val status = beaconPermissionStatus()
                    if (status == PmAuthorizationStatus.AUTHORIZED) {
                        beaconStatusCommandCallback(status, command, requestId)
                    } else {
                        beaconAuthorizeRequestId = requestId
                        requestBeaconPermission()
                    }
                    return 0u
                }
                // Defensive: should not happen because the WebView is
                // always hosted inside an Activity.
                beaconStatusCommandCallback(PmAuthorizationStatus.DENIED, command, requestId)
                return 0u
            }

            PMCommand.BEACON_ONCE -> {
                beaconOnceRequestIds.add(requestId)
                startBeaconRequest(command, requestId)
                return 0u
            }

            PMCommand.BEACON_WATCH -> {
                beaconWatchRequestIds.add(requestId)
                startBeaconRequest(command, requestId)
                return 0u
            }

            PMCommand.BEACON_CLEAR_WATCH -> {
                beaconWatchRequestIds.clear()
                stopBeaconRequestIfNoRequest()
            }
            //endregion

            //region Heading
            PMCommand.HEADING_WATCH -> {
                headingRequestIds.add(requestId)
                startSensorHeadingRequest()
                return 0u
            }

            PMCommand.HEADING_CLEAR_WATCH -> {
                headingRequestIds.clear()
                stopSensorHeadingRequest()
            }
            //endregion

        }

        commandCallback(command, requestId, mapOf())
        return 0u
    }

    private fun commandCallback(command: PMCommand, requestId: String, args: Map<String, Any>) {
        // JSON-encode every argument so that an attacker-influenced
        // `requestId` (which originates in the navigation URL) cannot escape
        // the JS string and execute arbitrary code in our page context.
        val argsJson = JSONObject(args).toString()
        val callback = "commandCallback(${JSONObject.quote(command.rawValue)},${JSONObject.quote(requestId)},$argsJson)"
        evaluateJavascript(callback) { _ -> }
    }

    //endregion

    //region Web Browse

    /**
     * URL schemes that the SDK is willing to hand to an in-app browser, an
     * external browser, or to `Intent.ACTION_VIEW`. Restricting the
     * allowlist prevents a compromised web layer from launching `file:`,
     * `intent:`, `javascript:`, `about:`, or `data:` URLs.
     */
    private val browseAllowedSchemes: Set<String> =
        setOf("http", "https", "tel", "mailto", "sms", "geo")

    private fun isSchemeAllowedForBrowse(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        return browseAllowedSchemes.contains(scheme)
    }

    private fun commandWebBrowse(command: PMCommand, commandUri: Uri) {
        commandUri.getQueryParameter("url")?.let { uriString ->
            parseBrowseUrl(uriString)?.let { uri ->
                if (!isSchemeAllowedForBrowse(uri)) {
                    Log.w(TAG, "commandWebBrowse: blocked disallowed scheme '${uri.scheme}'")
                    return@let
                }
                when (command) {
                    PMCommand.BROWSE_APP,
                    PMCommand.MAP_NAVIGATE -> {
                        openWebBrowseApp(uri)
                    }

                    PMCommand.BROWSE_IN_APP -> {
                        val sharedCookie = commandUri.getQueryParameter("sharedCookie") == "true"
                        if (sharedCookie) {
                            openWebBrowseActivity(uri)
                        } else {
                            openWebBrowseInApp(uri)
                        }
                    }

                    else -> {
                        // ignore
                    }
                }
            }
        }
    }

    private fun parseBrowseUrl(urlString: String): Uri? {
        try {
            urlString.toUri().let {
                if (it.authority?.isNotEmpty() == true) {
                    return it
                }
                if (it.scheme == "tel") {
                    return it
                }
                originalUrl?.let { originalUrl ->
                    val workUri = it.buildUpon()
                    originalUrl.scheme?.let { scheme ->
                        workUri.scheme(scheme)
                    }
                    originalUrl.authority?.let { authority ->
                        workUri.authority(authority)
                    }
                    return workUri.build()
                }
            }
        } catch (ex: Exception) {
            ex.message?.let {
                Log.d(TAG, it)
            }
        }
        return null
    }

    private fun openWebBrowseInApp(uri: Uri) {
        parentActivity?.let {
            CustomTabsIntent.Builder().build().launchUrl(it, uri)
        }
    }

    private fun openWebBrowseActivity(uri: Uri) {
        onOpenLinkListener?.onOpenLink(uri, true)
    }

    private fun openWebBrowseApp(uri: Uri) {
        onOpenLinkListener?.onOpenLink(uri, false)
    }

    //endregion

    //region Location

    private fun requestPermissions(permissions: Array<String>, requestCode: Int) {
        parentActivity?.let {
            ActivityCompat.requestPermissions(
                it,
                permissions,
                requestCode
            )
        }
    }

    private fun locationPermissionStatus(): PmLocationAuthorizationStatus {
        parentActivity?.let {
            if (ContextCompat.checkSelfPermission(
                    it,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                return PmLocationAuthorizationStatus.AUTHORIZED
            } else if (ActivityCompat.shouldShowRequestPermissionRationale(
                    it,
                    Manifest.permission.ACCESS_FINE_LOCATION
                )
            ) {
                // Previously denied without ticking "Don't ask again".
                return PmLocationAuthorizationStatus.DENIED
            }
            // "Don't ask again" denials are indistinguishable from a fresh
            // permission state, so we report them as `notDetermined`.
            return PmLocationAuthorizationStatus.NOT_DETERMINED
        }
        return PmLocationAuthorizationStatus.DENIED
    }

    /**
     * Shows a custom dialog to explain the rationale for requiring permissions.
     */
    private fun showPermissionRationaleDialog(
        permissions: Array<String>,
        requestCode: Int,
        title: String,
        message: String
    ) {
        AlertDialog.Builder(context)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                requestPermissions(permissions, requestCode)
            }
            .create()
            .show()
    }

    private fun requestLocationPermission() {
        val status = locationPermissionStatus()
        if (status == PmLocationAuthorizationStatus.AUTHORIZED) {
            updateLocationPermission(true)
        } else if (status == PmLocationAuthorizationStatus.DENIED) {
            showPermissionRationaleDialog(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                REQUEST_CODE_PERMISSIONS_LOCATION,
                context.getString(R.string.dialog_title_location_permission),
                context.getString(R.string.dialog_message_location_permission)
            )
        } else {
            requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                REQUEST_CODE_PERMISSIONS_LOCATION
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun startLocationRequest(isOnce: Boolean) {
        parentActivity?.let {
            if (locationPermissionStatus() !== PmLocationAuthorizationStatus.AUTHORIZED) {
                return
            }

            // Lazily initialise FusedLocationProviderClient.
            if (!::fusedLocationClient.isInitialized) {
                fusedLocationClient = LocationServices.getFusedLocationProviderClient(it)
            }

            if (isMeasuringLocation) {
                if (isOnce) {
                    lastLocation?.let { updateLocation(it, false) }
                }
                return
            }

            val locationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                maxUpdateIntervalMillis
            ).apply {
                setMinUpdateIntervalMillis(minUpdateIntervalMillis)
                setMinUpdateDistanceMeters(minUpdateDistanceMeters)
            }.build()

            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )

            isMeasuringLocation = true
        }
    }

    private fun stopLocationRequest() {
        if (!isMeasuringLocation) {
            return
        }
        if (::fusedLocationClient.isInitialized) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
        isMeasuringLocation = false
    }

    private fun startLocationRequest(command: PMCommand, requestId: String) {
        val status = locationPermissionStatus()
        parentActivity?.let {
            if (status != PmLocationAuthorizationStatus.AUTHORIZED) {
                requestLocationPermission()
            } else {
                startLocationRequest(command == PMCommand.LOCATION_ONCE)
            }
            return
        }
        // Fallback path: WebView is not currently hosted by an Activity, so
        // we cannot prompt for permission. Report the current status to
        // the web layer.
        commandCallback(command, requestId, mapOf("status" to status.rawValue))
    }

    private fun stopLocationRequestIfNoRequest() {
        if (locationWatchRequestIds.isEmpty() && locationOnceRequestIds.isEmpty()) {
            stopLocationRequest()
        }
    }

    private fun locationStatusCommandCallback(
        status: PmLocationAuthorizationStatus,
        command: PMCommand,
        requestId: String
    ) {
        commandCallback(command, requestId, mapOf("status" to status.rawValue))
    }

    private fun updateLocationPermission(isGranted: Boolean) {
        val args = mutableMapOf<String, Any>()
        if (isGranted) {
            args["status"] = PmLocationAuthorizationStatus.AUTHORIZED.rawValue
        } else {
            args["status"] = PmLocationAuthorizationStatus.DENIED.rawValue
        }
        if (!isGranted) {
            for (item in locationOnceRequestIds) {
                commandCallback(PMCommand.LOCATION_ONCE, item, args)
            }
            for (item in locationWatchRequestIds) {
                commandCallback(PMCommand.LOCATION_WATCH, item, args)
            }
            locationOnceRequestIds.clear()
            locationWatchRequestIds.clear()
        }

        locationAuthorizeRequestId?.let {
            commandCallback(PMCommand.LOCATION_AUTHORIZE, it, args)
        }
        locationAuthorizeRequestId = null
    }

    private fun updateLocation(location: Location?, hasError: Boolean) {
        val args = mutableMapOf<String, Any>()
        val status = locationPermissionStatus()
        if (status == PmLocationAuthorizationStatus.AUTHORIZED) {
            args["status"] = PmLocationAuthorizationStatus.AUTHORIZED.rawValue
        } else {
            args["status"] = PmLocationAuthorizationStatus.DENIED.rawValue
        }

        location?.let {
            args["lat"] = it.latitude
            args["lng"] = it.longitude
            if (it.hasBearing()) {
                args["heading"] = it.bearing
            }
        }

        if (hasError) {
            args["hasError"] = true
        }

        locationOnceRequestIds.forEach {
            commandCallback(PMCommand.LOCATION_ONCE, it, args)
        }

        locationWatchRequestIds.forEach {
            commandCallback(PMCommand.LOCATION_WATCH, it, args)
        }

        locationOnceRequestIds.clear()
        stopLocationRequestIfNoRequest()
    }

    //endregion

    //region Beacon

    /**
     * Requests the runtime permissions required for BLE beacon scanning and,
     * once granted, kicks off scanning.
     */
    private fun requestBeaconPermission() {
        parentActivity?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (it.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_DENIED
                    || it.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_DENIED
                ) {
                    requestPermissions(
                        arrayOf(
                            Manifest.permission.BLUETOOTH_SCAN,
                            Manifest.permission.ACCESS_FINE_LOCATION
                        ), REQUEST_CODE_PERMISSIONS_BEACON
                    )
                } else {
                    initBeaconReceiverIfNeeded(it, true)
                }
            } else {
                if ((it.applicationContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_DENIED)) {
                    requestPermissions(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION
                        ), REQUEST_CODE_PERMISSIONS_BEACON
                    )
                } else {
                    initBeaconReceiverIfNeeded(it, true)
                }
            }
        }
    }

    /**
     * Initializes the BLE scanner. If `startScanning` is true, scanning is
     * kicked off immediately afterwards.
     */
    private fun initBeaconReceiverIfNeeded(context: Context, startScanning: Boolean) {
        parentActivity?.let {
            if (bluetoothLeScanner == null) {
                val bluetoothManager = it.getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
                val bluetoothAdapter = bluetoothManager.adapter
                bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
                Log.d(TAG_BEACON, "initBeaconReceiver: ble scanner is created")
            }

            if (startScanning) {
                mainHandler.post { startScanningBeacon() }
            }
        }
    }

    /**
     * Starts the BLE scan. Does nothing if there is no configured listening
     * UUID or if a scan is already in flight.
     */
    @SuppressLint("MissingPermission")
    private fun startScanningBeacon() {
        if (beaconListeningUuid == null) {
            // No (or invalid) UUID configured — refuse to scan rather than
            // accept every Apple-manufacturer advertisement.
            Log.w(TAG_BEACON, "startScanningBeacon: no listening uuid configured, skipping")
            return
        }
        if (isScanningBle) {
            Log.w(TAG_BEACON, "startScanningBeacon: already scanning")
            return
        }
        synchronized(this) {
            val filter = ScanFilter.Builder()
                .setManufacturerData(0x004C, byteArrayOf()) // Apple — iBeacon manufacturer id
                .build()

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()

            bluetoothLeScanner?.startScan(listOf(filter), settings, leScanCallback)
            isScanningBle = true
            Log.d(TAG_BEACON, "startScanningBeacon: ble scan is now started")
        }
    }

    /**
     * Receives BLE scan results. Callbacks arrive on a system-chosen binder
     * thread, so any work that touches shared state (`beaconBuffer` in
     * particular) is bounced onto the main looper.
     */
    private val leScanCallback: ScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            super.onScanResult(callbackType, result)

            val beacon = parseBeacon(result) ?: return
            Log.d(TAG_BEACON, "onScanResult: detected $beacon")

            mainHandler.post {
                updateBeacon(beacon, false)
            }
        }
    }

    private fun parseBeacon(result: ScanResult): PmBeaconDto? {
        result.scanRecord?.let { scanRecord ->
            val bytes = scanRecord.bytes
            if (bytes.size > 30) {
                val sb = StringBuilder()

                // UUID
                for (i in 9..24) {
                    sb.append(String.format("%02x", bytes[i]))
                    if (i == 12 || i == 14 || i == 16 || i == 18) {
                        sb.append("-")
                    }
                }

                val uuid = sb.toString()
                // We never want to forward beacons that don't match the
                // caller's configured UUID. The null check is belt-and-
                // braces: `startScanningBeacon` already refuses to scan
                // when `beaconListeningUuid` is null.
                val listening = beaconListeningUuid ?: return null
                if (!uuid.equals(listening, ignoreCase = true)) {
                    return null
                }

                // Major/Minor are encoded big-endian.
                val major = ((bytes[25].toInt() and 0xFF) shl 8) or (bytes[26].toInt() and 0xFF)
                val minor = ((bytes[27].toInt() and 0xFF) shl 8) or (bytes[28].toInt() and 0xFF)

                return PmBeaconDto(uuid, major, minor, result.rssi)
            }
        }

        return null
    }

    /**
     * Gets the status of permissions required for beacon reception.
     */
    private fun beaconPermissionStatus(): PmAuthorizationStatus {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val bluetoothScan = permissionStatus(Manifest.permission.BLUETOOTH_SCAN)
            val accessFineLocation = permissionStatus(Manifest.permission.ACCESS_FINE_LOCATION)

            if (bluetoothScan == PmAuthorizationStatus.AUTHORIZED
                && accessFineLocation == PmAuthorizationStatus.AUTHORIZED
            ) {
                return PmAuthorizationStatus.AUTHORIZED
            }

            if (bluetoothScan == PmAuthorizationStatus.DENIED
                || accessFineLocation == PmAuthorizationStatus.DENIED
            ) {
                return PmAuthorizationStatus.DENIED
            }

            return PmAuthorizationStatus.NOT_DETERMINED

        } else {
            val accessFineLocation = permissionStatus(Manifest.permission.ACCESS_FINE_LOCATION)
            return accessFineLocation
        }
    }

    /**
     * Gets the status of a specific permission.
     */
    private fun permissionStatus(permission: String): PmAuthorizationStatus {
        parentActivity?.let {
            if (ContextCompat.checkSelfPermission(
                    it,
                    permission
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                return PmAuthorizationStatus.AUTHORIZED
            } else if (ActivityCompat.shouldShowRequestPermissionRationale(it, permission)) {
                // Previously denied without ticking "Don't ask again".
                return PmAuthorizationStatus.DENIED
            }
            // "Don't ask again" denials are indistinguishable from a fresh
            // permission state, so we report them as `notDetermined`.
            return PmAuthorizationStatus.NOT_DETERMINED
        }
        return PmAuthorizationStatus.DENIED
    }

    @SuppressLint("MissingPermission")
    private fun startBeaconRequest(isOnce: Boolean) {
        if (beaconListeningUuid == null) {
            Log.w(TAG_BEACON, "startBeaconRequest: no listening uuid configured, skipping")
            return
        }
        val permissionStatus = beaconPermissionStatus()
        if (permissionStatus !== PmAuthorizationStatus.AUTHORIZED) {
            Log.w(
                TAG_BEACON,
                "startBeaconRequest: cannot start ble scan because given permission is '${permissionStatus.rawValue}'"
            )
            return
        }

        parentActivity?.let {
            initBeaconReceiverIfNeeded(it, true)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopBeaconRequest() {
        if (!isScanningBle) {
            return
        }
        bluetoothLeScanner?.stopScan(leScanCallback)
        isScanningBle = false
        Log.d(TAG_BEACON, "stopBeaconRequest: ble scan is now stopped")
    }

    @SuppressLint("MissingPermission")
    private fun pauseScanningBeaconIfNeeded() {
        if (isScanningBle) {
            bluetoothLeScanner?.stopScan(leScanCallback)
            isScanningBle = false
            isScanningBlePaused = true
            Log.d(TAG_BEACON, "pauseScanningBeaconIfNeeded: ble scan is paused")
        }
    }

    private fun resumeScanningBeaconIfNeeded() {
        if (isScanningBlePaused) {
            startScanningBeacon()
            isScanningBlePaused = false
            Log.d(TAG_BEACON, "resumeScanningBeaconIfNeeded: ble scan is resumed")
        }
    }

    /**
     * Requests beacon information (starts BLE scan).
     */
    private fun startBeaconRequest(command: PMCommand, requestId: String) {
        val status = beaconPermissionStatus()
        parentActivity?.let {
            if (status != PmAuthorizationStatus.AUTHORIZED) {
                requestBeaconPermission()
            } else {
                startBeaconRequest(command == PMCommand.BEACON_ONCE)
            }
            return
        }
        commandCallback(command, requestId, mapOf("status" to status.rawValue))
    }

    /**
     * Stops requesting beacon information (stops BLE scan).
     */
    private fun stopBeaconRequestIfNoRequest() {
        if (beaconWatchRequestIds.isEmpty() && beaconOnceRequestIds.isEmpty()) {
            stopBeaconRequest()
        }
    }

    private fun destroyBeacon() {
        beaconAuthorizeRequestId = null
        beaconOnceRequestIds.clear()
        beaconWatchRequestIds.clear()
        beaconBuffer.clear()
        stopBeaconRequest()
    }

    /**
     * Sends the beacon permission status to the web.
     */
    private fun beaconStatusCommandCallback(
        status: PmAuthorizationStatus,
        command: PMCommand,
        requestId: String
    ) {
        commandCallback(command, requestId, mapOf("status" to status.rawValue))
    }

    /**
     * Called when the runtime permission result for a beacon-related
     * request has been delivered.
     */
    private fun updateBeaconPermission(isGranted: Boolean) {
        parentActivity?.let {
            if (isGranted) {
                initBeaconReceiverIfNeeded(it, true)
            }

            val args = mutableMapOf<String, Any>()
            if (isGranted) {
                args["status"] = PmAuthorizationStatus.AUTHORIZED.rawValue
            } else {
                args["status"] = PmAuthorizationStatus.DENIED.rawValue
            }

            // Reply to the in-flight beacon.authorize request, if any.
            // Historically this incorrectly fired with LOCATION_AUTHORIZE,
            // which left the web side waiting forever for a beacon reply.
            beaconAuthorizeRequestId?.let {
                commandCallback(PMCommand.BEACON_AUTHORIZE, it, args)
            }
            beaconAuthorizeRequestId = null

            if (!isGranted) {
                // Permission denied → fail any pending beacon reads so the
                // web side can move on.
                args["hasError"] = true

                for (item in beaconOnceRequestIds) {
                    commandCallback(PMCommand.BEACON_ONCE, item, args)
                }
                for (item in beaconWatchRequestIds) {
                    commandCallback(PMCommand.BEACON_WATCH, item, args)
                }
                beaconOnceRequestIds.clear()
                beaconWatchRequestIds.clear()
            }
        }
    }

    /**
     * Sends information about detected beacons to the web. Must be invoked
     * on the main looper.
     */
    private fun updateBeacon(beacon: PmBeaconDto?, hasError: Boolean) {
        if (hasError) {
            val args = mutableMapOf<String, Any>()
            args["hasError"] = true

            val status = beaconPermissionStatus()
            if (status == PmAuthorizationStatus.AUTHORIZED) {
                args["status"] = PmAuthorizationStatus.AUTHORIZED.rawValue
            } else {
                args["status"] = PmAuthorizationStatus.DENIED.rawValue
            }

            args["beacons"] = mutableListOf<Map<String, Any>>()

            beaconCommandCallback(args)

            beaconBuffer.clear()
            lastBeaconUpdateTime = Date()
            return
        }

        beacon?.let {
            beaconBuffer.add(it)

            if (beaconBufferingWindow > 0) {
                val elapsed = Date().time - lastBeaconUpdateTime.time
                if (elapsed > beaconBufferingWindow) {
                    flushBeaconBuffer()
                } else if (!isBeaconBufferFlushReserved) {
                    reserveFlushBeaconBuffer()
                }
            } else {
                flushBeaconBuffer()
            }
        }
    }

    private fun reserveFlushBeaconBuffer() {
        if (isBeaconBufferFlushReserved) {
            return
        }
        isBeaconBufferFlushReserved = true
        mainHandler.postDelayed(
            {
                flushBeaconBuffer()
                isBeaconBufferFlushReserved = false
            }, beaconBufferingWindow
        )
    }

    private fun flushBeaconBuffer() {
        if (beaconBuffer.size > 0) {
            val args = mutableMapOf<String, Any>()
            var beacons = mutableListOf<Map<String, Any>>()

            for (beacon in beaconBuffer) {
                val b = mutableMapOf<String, Any>()
                b["uuid"] = beacon.uuid
                b["major"] = beacon.major
                b["minor"] = beacon.minor
                b["rssi"] = beacon.rssi
                b["timestamp"] = beacon.timestamp.time
                beacons.add(b)
            }

            beaconBuffer.clear()

            args["beacons"] = beacons

            beaconCommandCallback(args)
        }

        lastBeaconUpdateTime = Date()
    }

    private fun beaconCommandCallback(args: Map<String, Any>) {
        beaconOnceRequestIds.forEach {
            commandCallback(PMCommand.BEACON_ONCE, it, args)
        }

        beaconWatchRequestIds.forEach {
            commandCallback(PMCommand.BEACON_WATCH, it, args)
        }

        beaconOnceRequestIds.clear()
        stopBeaconRequestIfNoRequest()
    }

    //endregion

    //region Heading

    /**
     * Starts requesting heading updates.
     */
    private fun startSensorHeadingRequest() {
        if (sensorHeadingListener != null) {
            return
        }
        parentActivity?.let {

            val sensorManager = it.getSystemService(Context.SENSOR_SERVICE) as SensorManager

            sensorHeadingListener = object : SensorEventListener {
                private val gravity = FloatArray(3)
                private val geomagnetic = FloatArray(3)

                override fun onSensorChanged(event: SensorEvent) {
                    when (event.sensor.type) {
                        Sensor.TYPE_ACCELEROMETER -> {
                            System.arraycopy(event.values, 0, gravity, 0, event.values.size)
                        }

                        Sensor.TYPE_MAGNETIC_FIELD -> {
                            System.arraycopy(event.values, 0, geomagnetic, 0, event.values.size)
                        }
                    }

                    if (gravity.isNotEmpty() && geomagnetic.isNotEmpty()) {
                        val rotationMatrix = FloatArray(9)
                        val inclinationMatrix = FloatArray(9)

                        if (SensorManager.getRotationMatrix(
                                rotationMatrix,
                                inclinationMatrix,
                                gravity,
                                geomagnetic
                            )
                        ) {
                            val orientation = FloatArray(3)
                            SensorManager.getOrientation(rotationMatrix, orientation)

                            val azimuthInRadians = orientation[0]
                            val azimuthInDegrees =
                                Math.toDegrees(azimuthInRadians.toDouble()).toFloat()

                            val magneticHeading: Int = Math.round((azimuthInDegrees + 360) % 360)
                            lastMagneticHeading = magneticHeading

                            // Throttle updates to one per `magneticHeadingPushInterval`.
                            val now = Date()
                            if (now.time - lastMagneticHeadingNotifiedAt.time > magneticHeadingPushInterval) {
                                onUpdateHeading(magneticHeading)
                                lastMagneticHeadingNotifiedAt = now
                            }
                        }
                    }
                }

                override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
            }

            val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            sensorManager.registerListener(
                sensorHeadingListener,
                accelerometer,
                SensorManager.SENSOR_DELAY_UI
            )

            val magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
            sensorManager.registerListener(
                sensorHeadingListener,
                magnetometer,
                SensorManager.SENSOR_DELAY_UI
            )

            Log.d(TAG_HEADING, "heading sensor is now started")
        }
    }

    /**
     * Stops requesting heading updates and unregisters the underlying
     * sensor listener.
     */
    private fun stopSensorHeadingRequest() {
        parentActivity?.let {
            if (sensorHeadingListener != null) {
                val sensorManager = it.getSystemService(Context.SENSOR_SERVICE) as SensorManager

                val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                sensorManager.unregisterListener(sensorHeadingListener, accelerometer)

                val magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                sensorManager.unregisterListener(sensorHeadingListener, magnetometer)

                sensorHeadingListener = null

                Log.d(TAG_HEADING, "heading sensor is now stopped")
            }
        }
    }

    /**
     * Pauses heading update requests for backgrounding.
     */
    private fun pauseSensorHeadingRequestIfNeeded() {
        Log.d(TAG_HEADING, "pausing heading sensor")
        stopSensorHeadingRequest()
    }

    /**
     * Resumes heading update requests when foregrounded — but only when
     * a watcher is still subscribed.
     */
    private fun resumeSensorHeadingRequestIfNeeded() {
        if (headingWatcherExists()) {
            Log.d(TAG_HEADING, "resuming heading sensor")
            startSensorHeadingRequest()
        }
    }

    private fun headingWatcherExists(): Boolean {
        return headingRequestIds.isNotEmpty()
    }

    /**
     * Releases heading-related resources. Mirrors `destroyBeacon`.
     */
    private fun destroyHeading() {
        headingRequestIds.clear()
        stopSensorHeadingRequest()
    }

    /**
     * Notifies the web of the updated device heading.
     */
    private fun onUpdateHeading(heading: Int) {
        val args = mutableMapOf<String, Any>()
        args["heading"] = heading

        headingRequestIds.forEach {
            commandCallback(PMCommand.HEADING_WATCH, it, args)
        }
    }

    //endregion

    /**
     * Handles the result of a runtime permission request.
     *
     * This method must be called from the parent Activity's or Fragment's `onRequestPermissionsResult`
     * callback to forward the result to the WebView. It is used for handling permissions such as
     * geolocation, camera, microphone, and beacons.
     *
     * @param requestCode The integer request code originally supplied to `requestPermissions()`.
     * @param grantResults The grant results for the corresponding permissions, which is either
     * [PackageManager.PERMISSION_GRANTED] or [PackageManager.PERMISSION_DENIED].
     */
    fun handlePermissionResult(requestCode: Int, grantResults: IntArray) {
        val allGranted =
            !(grantResults.isEmpty() || grantResults.any { it != PackageManager.PERMISSION_GRANTED })

        when (requestCode) {
            PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                    activePermissionRequest?.grant(activePermissionRequest?.resources)
                } else {
                    activePermissionRequest?.deny()
                }
                activePermissionRequest = null
            }

            GEOLOCATION_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    geolocationPermissionsCallback?.invoke(geolocationOrigin, true, false)
                } else {
                    geolocationPermissionsCallback?.invoke(geolocationOrigin, false, false)
                }
                geolocationPermissionsCallback = null
                geolocationOrigin = null
            }

            REQUEST_CODE_PERMISSIONS_LOCATION -> {
                updateLocationPermission(allGranted)
            }

            REQUEST_CODE_PERMISSIONS_BEACON -> {
                updateBeaconPermission(allGranted)
            }
        }
    }

    /**
     * Handles the result from a file chooser intent launched by the WebView.
     *
     * This method must be called from the parent Activity's or Fragment's `onActivityResult` callback
     * (or the modern Activity Result API equivalent). It passes the selected file's URI(s) back to the
     * WebView to complete the file upload process.
     *
     * @param requestCode The integer request code, which should be `FILE_CHOOSER_REQUEST_CODE`.
     * @param resultCode The integer result code returned by the child activity.
     * @param data An `Intent`, which can return result data to the caller.
     */
    fun handleFileChooserResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FILE_CHOOSER_REQUEST_CODE) {
            var results: Array<Uri>? = null
            if (resultCode == Activity.RESULT_OK) {
                if (data != null) {
                    val dataString = data.dataString
                    if (dataString != null) {
                        results = arrayOf(dataString.toUri())
                    } else {
                        // Multi-select path.
                        results = data.clipData?.let {
                            (0 until it.itemCount).map { i -> it.getItemAt(i).uri }.toTypedArray()
                        }
                    }
                }
            }
            filePathCallback?.onReceiveValue(results)
            filePathCallback = null
        }
    }

    companion object {
        const val PERMISSION_REQUEST_CODE = 100
        const val GEOLOCATION_PERMISSION_REQUEST_CODE = 101
        const val FILE_CHOOSER_REQUEST_CODE = 102

        // The following constants are ported from a previous version
        const val REQUEST_CODE_PERMISSIONS_LOCATION = 201
        const val REQUEST_CODE_PERMISSIONS_BEACON = 202
    }

    //region lifecycle

    /**
     * Pauses background tasks such as location, beacon, and sensor updates.
     *
     * This method should be called from the parent Activity's or Fragment's `onPause()`
     * lifecycle method to conserve battery and system resources when the app is not in the
     * foreground.
     */
    fun activityPause() {
        if (locationOnceRequestIds.isNotEmpty() || locationWatchRequestIds.isNotEmpty()) {
            stopLocationRequest()
        }
        pauseScanningBeaconIfNeeded()
        pauseSensorHeadingRequestIfNeeded()

        // Android may suspend or kill the process shortly after pause, so
        // any pending `postDelayed` callback would fire at an
        // unpredictable wall-clock moment on resume. Cancel the pending
        // retry and reset the backoff so [activityResume] can start
        // clean.
        resetRetryState()
    }

    /**
     * Resumes background tasks that were paused by `activityPause()`.
     *
     * This method should be called from the parent Activity's or Fragment's `onResume()`
     * lifecycle method to restart location, beacon, and sensor updates when the app returns
     * to the foreground.
     */
    fun activityResume() {
        if (locationOnceRequestIds.isNotEmpty() || locationWatchRequestIds.isNotEmpty()) {
            startLocationRequest(locationWatchRequestIds.isEmpty())
        }
        resumeScanningBeaconIfNeeded()
        resumeSensorHeadingRequestIfNeeded()

        // If the initial load had already failed at least once when the
        // user backgrounded the app, fire one immediate fresh attempt on
        // resume rather than leaving the splash up indefinitely. The
        // pending backoff was cancelled and the counter zeroed on
        // [activityPause], so a subsequent failure restarts the
        // sequence from one second.
        if (!hasWebReady && hasInitialLoadFailed) {
            scheduleImmediateRetry()
        }
    }

    /**
     * Cleans up all resources used by the WebView.
     *
     * This method must be called from the parent Activity's or Fragment's `onDestroy()`
     * lifecycle method to prevent memory leaks. It stops all running services, clears the
     * WebView's history and state, and calls the underlying `destroy()` method.
     */
    fun activityDestroy() {
        cancelPendingRetry()
        destroyBeacon()
        destroyHeading()
        loadUrl("about:blank")
        clearHistory()
        removeAllViews()
        destroy()
    }

    //endregion

    /**
     * Interface definition for a callback to be invoked when a link is opened within the Platinumaps.
     *
     * This listener can be used to handle various types of links, not just web URLs, but also other schemes like 'tel:' and 'mailto:'.
     */
    interface OnOpenLinkListener {

        /**
         * Called when a link is opened.
         *
         * @param url The URI of the link to be opened, which can be an HTTP URL or other URI schemes like 'tel:' and 'mailto:'.
         * @param sharedCookie A boolean flag that is true when user information needs to be passed to the link, such as for temporary download benefits or external link benefits.
         */
        fun onOpenLink(url: Uri, sharedCookie: Boolean)
    }
}
