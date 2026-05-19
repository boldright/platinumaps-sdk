import UIKit
import WebKit
import SafariServices
import CoreLocation
import os

/// Delegate that the host application may set on `PMMainViewController` to take
/// over the handling of links that the embedded Platinumaps web app wants to
/// open. When no delegate is set the SDK falls back to `SFSafariViewController`
/// for HTTPS/HTTP and `UIApplication.open` for known custom schemes.
///
/// The delegate is invoked on the main actor.
@MainActor
protocol PMMainViewControllerDelegate: AnyObject {
    /// Called when the web app requests that a link be opened outside the map.
    /// - Parameters:
    ///   - url: The destination URL. Schemes are restricted by the SDK to a
    ///     conservative allowlist (`http`, `https`, `tel`, `mailto`, `sms`,
    ///     `geo`); anything else is dropped before reaching the delegate.
    ///   - sharedCookie: `true` when the web app marked the link as one that
    ///     must carry the current session — for example, stamp-rally reward
    ///     downloads. The host should open such links in an in-app browser
    ///     that shares cookies with the embedded WebView. `false` when the
    ///     link is safe to hand off to the system browser.
    func openLink(_ url: URL, sharedCookie: Bool)
}

/// Hosts the Platinumaps `WKWebView` and bridges native capabilities
/// (location, heading, iBeacon ranging, in-app browser, app store review,
/// universal-link relay) into the web app via the `command://` URL scheme.
///
/// Lifecycle: the controller wires itself as the `WKNavigationDelegate`,
/// `WKUIDelegate`, and `CLLocationManagerDelegate`. It registers
/// `UIApplication.willEnterForeground` / `didEnterBackground` observers on
/// first appearance and tears them down in `deinit`. All public state is
/// expected to be read or written on the main actor.
///
/// Bridge protocol:
///   * Web → native: `command://<name>?requestId=<id>&...` is intercepted in
///     `decidePolicyFor` and dispatched by `runCommand`.
///   * Native → web: replies are sent via
///     `commandCallback('<name>', '<requestId>', <argsJSON>)` and unsolicited
///     pushes via `commandPush('<name>', <argsJSON>)`. All three arguments are
///     JSON-encoded to keep attacker-influenced data out of JS context.
class PMMainViewController: UIViewController {

    /// The set of URL schemes the SDK is willing to hand to
    /// `SFSafariViewController` / `UIApplication.open` when the web app issues
    /// `browse.app` / `browse.inapp` / `map.navigate`. Restricting the
    /// allowlist protects against the web side trying to launch
    /// `javascript:`, `file:`, `about:`, or `data:` URLs.
    private static let browseAllowedSchemes: Set<String> = [
        "http", "https", "tel", "mailto", "sms", "geo",
    ]

    enum PMCommand: String, Sendable {
        case webReady = "web.ready"
        case webWillReload = "web.willreload"
        case locationStatus = "location.status"
        case locationAuthorize = "location.authorize"
        case locationOnce = "location.once"
        case locationWatch = "location.watch"
        case locationClearWatch = "location.clearwatch"
        case stampRallyQrCode = "stamprally.qrcode"
        case browseApp = "browse.app"
        case browseInApp = "browse.inapp"
        case appInfo = "app.info"
        case appDetect = "app.detect"
        case appReview = "app.review"
        case mapNavigate = "map.navigate"
        case searchFocus = "search.focus"

        //#region Beacon
        case beaconAuthorize = "beacon.authorize"
        case beaconOnce = "beacon.once"
        case beaconWatch = "beacon.watch"
        case beaconClearWatch = "beacon.clearwatch"
        //#endregion
    }

    private weak var mainWebView: PMWebView!
    private weak var coverImageView: UIImageView!

    public weak var delegate: PMMainViewControllerDelegate?

    /// Required. The URL-safe slug of the map to display. The final URL is
    /// `https://platinumaps.jp/maps/<mapSlug>`.
    public var mapSlug: String? = nil

    /// Optional. Extra query parameters appended to the map URL.
    public var mapQuery: [String: String] = [:]

    /// Optional. Forces the map UI language. When `nil` the WebView's
    /// `Accept-Language` (derived from `UserDefaults.standard`'s
    /// `AppleLanguages`) determines the language.
    public var mapLocale: PMLocale? = nil

    /// Optional. The numeric App Store ID (e.g. `"1234567890"`) used by the
    /// `app.review` command to open the App Store review page.
    public var appStoreId: String? = nil

    /// Optional. Splash image shown while the web layer boots; faded out once
    /// the web layer signals `web.ready`.
    public var coverImage: UIImage? = nil

    /// Optional. Opaque user identifier the web app may consume via
    /// `app.info`.
    public var userId: String? = nil

    /// Optional. Opaque shared secret the web app may consume via `app.info`.
    /// Treat this as sensitive: only set it when the host application has a
    /// legitimate need for the web layer to authenticate the user.
    public var secretKey: String? = nil

    /// Optional. When non-zero, the SDK reports `safearea` to the web with
    /// the bottom inset zeroed out — useful when the host already adds its
    /// own bottom inset (e.g. a tab bar).
    public var offsetBottom: Int = 0

    /// Optional. URL captured from a Universal Link / Custom URL Scheme launch
    /// that should be forwarded to the web app once it is ready. Use
    /// `pushLaunchURL(_:)` from outside the SDK to push a URL at runtime.
    public var launchURL: URL? = nil

    private var isFirstViewAppear = false

    /// `true` while the WebView is loading a top-level page.
    private var isWebViewLoading = false

    /// `true` once the web layer has signalled `web.ready` at least once.
    private var hasWebReady = false

    /// Number of failed initial-load attempts since the last `web.ready`,
    /// `web.willreload`, or background reset. Drives the exponential
    /// backoff in `scheduleNextRetry()`.
    private var retryAttempt: Int = 0

    /// `true` once the initial load has failed at least once and not yet
    /// succeeded. Survives the background-reset path so foreground re-entry
    /// can tell "user is staring at a stuck splash" apart from "load is
    /// still in flight" and fire an immediate retry only in the former case.
    /// Cleared on `web.ready` and `web.willreload`.
    private var hasInitialLoadFailed: Bool = false

    /// Handle to the currently-pending retry, if any. Cancelled when the
    /// retry needs to be replaced, when the user backgrounds the app, or
    /// when the controller is torn down.
    private var retryTask: Task<Void, Never>? = nil

    private var _locationManager: CLLocationManager? = nil
    private var locationManager: CLLocationManager {
        if _locationManager == nil {
            _locationManager = CLLocationManager()
        }
        return _locationManager!
    }

    private var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    private var isMeasuringLocation = false

    private var originalUrl = URLComponents()

    /// Timestamp of the most recent WebView load — retained for future
    /// timeout / telemetry use.
    private var webViewLoadingAt: Date? = nil

    /// Timestamp captured at controller instantiation. Used to enforce a
    /// minimum cover-image display window so the splash does not flash.
    private let loadAt = Date()

    /// `requestId` of the in-flight `location.authorize` command. Cleared
    /// once the authorization status resolves to something other than
    /// `.notDetermined`.
    private var locationAuthorizeRequestId: String? = nil

    /// `requestId` of the in-flight `beacon.authorize` command. Tracked
    /// separately from `locationAuthorizeRequestId` so that the reply is
    /// dispatched under the original command name; otherwise the web side
    /// listens on `command.beacon.authorize.<id>` while the SDK fires
    /// `command.location.authorize.<id>` and the Promise hangs forever.
    private var beaconAuthorizeRequestId: String? = nil

    /// Active `requestId`s issued by `location.watch`.
    private var locationWatchRequestIds: [String] = []

    /// Pending `requestId`s issued by `location.once`. Each entry is fired
    /// exactly once when the next valid location/heading pair arrives, then
    /// the array is emptied.
    private var locationOnceRequestIds: [String] = []

    /// State machine that coordinates the first location callback after we
    /// start ranging. `0` = waiting for the first `didUpdateLocations`,
    /// `1` = first location seen, sleeping briefly so a heading sample can
    /// catch up (heading is delivered slightly later than the first
    /// location), `2` = steady state, callbacks flow through immediately.
    private var locationCallbackStatus = 0

    /// Most-recent heading sample, kept because `CLLocationManager.heading`
    /// can momentarily return `nil` after the first delivery.
    private var lastHeading: CLHeading? = nil

    /// `true` while the "Location Services restricted" alert is on screen.
    /// Prevents duplicate alerts when both the location and beacon paths
    /// try to surface the same dialog.
    private var isAlertPresentedForLocationRestricted = false

    /// `true` while the "Location permission denied" alert is on screen.
    private var isAlertPresentedForLocationDenied = false

    // MARK: Beacon Members
    /// Optional. iBeacon UUID (hyphenated) to range. When `nil` the beacon
    /// path is disabled and `beacon.*` commands resolve as no-ops.
    var beaconUuid: String?
    private var useBeacon = false
    private var beaconRegion: CLBeaconRegion!
    private var beaconWatchRequestIds: [String] = []    {
        didSet {
#if DEBUG
            logBeacon("didSet: beaconWatchRequestIds = \(beaconWatchRequestIds)")
#endif
        }
    }
    private var beaconOnceRequestIds: [String] = []
    private var isMonitoringBeacon = false {
        didSet {
#if DEBUG
            logBeacon("didSet: isMonitoringBeacon = \(isMonitoringBeacon)")
#endif
        }
    }
    private var isRangingBeacon = false {
        didSet {
#if DEBUG
            logBeacon("didSet: isRangingBeacon = \(isRangingBeacon)")
#endif
        }
    }
    /// `true` while ranging/monitoring was paused for background mode.
    /// Currently only consumed by debug logging.
    private var isBeaconPaused = false
    // MARK: Other Settings

    /// Enable WebKit Inspector (`isInspectable` on iOS 16.4+) for the
    /// embedded `WKWebView`. Off by default.
    public var isWebViewInspectable = false

    /// Platinumaps origin. Swapped out only in tests / staging.
    private var mapOrigin = "https://platinumaps.jp"

    /// Lazy handle to the SDK's resource bundle. The bundle is registered as
    /// an SPM resource (`Package.swift` → `.process("Platinumaps.bundle")`)
    /// and contains the localized strings used by the permission alerts.
    private var _bundle: Bundle? = nil
    private var bundle: Bundle {
        if _bundle == nil {
            _bundle = Bundle(path: Bundle.main.path(forResource: "Platinumaps", ofType: "bundle")!)
        }
        return _bundle!
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        if mapSlug?.isEmpty != false {
            fatalError("MapSlug is empty")
        }

        let webViewConfig = WKWebViewConfiguration()
        webViewConfig.applicationNameForUserAgent = "Platinumaps/2.0.0"
        webViewConfig.allowsInlineMediaPlayback = true
        webViewConfig.mediaTypesRequiringUserActionForPlayback = .audio
        let webView = PMWebView(frame: CGRect.zero, configuration: webViewConfig)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if isWebViewInspectable {
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
        }

        mainWebView = webView;

        if let image = coverImage {
            let imageView = UIImageView(frame: view.bounds)
            imageView.translatesAutoresizingMaskIntoConstraints = true
            view.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: view.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            imageView.image = image
            coverImageView = imageView;
        }

        isFirstViewAppear = true

        locationManager.delegate = self
        initBeaconIfNeeded()
    }

    deinit {
        // Best-effort cleanup: stop any in-flight sensors and detach observers
        // so callbacks cannot fire into a deallocated controller. We touch
        // `_locationManager` directly to avoid lazily creating one in deinit.
        NotificationCenter.default.removeObserver(self)
        retryTask?.cancel()
        if let manager = _locationManager {
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            manager.stopMonitoringSignificantLocationChanges()
            if let region = beaconRegion {
                manager.stopRangingBeacons(satisfying: region.beaconIdentityConstraint)
                manager.stopMonitoring(for: region)
            }
            manager.delegate = nil
        }
    }

    @objc private func reloadWebView(_ sender: Any?) {
        showCoverImageView()
        if mainWebView.canGoBack {
            mainWebView.goBack()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.reloadWebView(nil)
            }
        } else if mainWebView.url != nil {
            mainWebView.reload()
        } else if let url = originalUrl.url {
            mainWebView.load(URLRequest(url: url))
        }
    }

    @objc private func openAppSettings(_ sender: Any?) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {

        super.viewDidAppear(animated)
        if isFirstViewAppear {
            let path = "/maps/\(mapSlug!)"
            var urlComp = URLComponents(string: "\(mapOrigin)\(path)")!

            var queryItems = [URLQueryItem]();

            // `culture` is normally derived from the WebView's
            // `Accept-Language` header (which itself follows the host app's
            // `AppleLanguages`). The explicit override is kept for hosts that
            // need to pin the map language independently of the app.
            if let mapLocale = mapLocale {
                queryItems.append(URLQueryItem(name: "culture", value: mapLocale.rawValue))
            }

            queryItems.append(URLQueryItem(name: "native", value: "1"))
            mapQuery.forEach { item in
                queryItems.append(URLQueryItem(name: item.key, value: item.value))
            }
            // Safe-area insets are only valid after the view has been laid
            // out, so we capture them here in `viewDidAppear`.
            let safeAreaTop = self.view.safeAreaInsets.top
            var safeAreaBottom = self.view.safeAreaInsets.bottom
            if (offsetBottom > 0) {
                safeAreaBottom = 0;
            }
            queryItems.append(URLQueryItem(name: "safearea", value: "\(safeAreaTop),\(safeAreaBottom)"));
            urlComp.queryItems = queryItems;

            if let url = urlComp.url {
                originalUrl = urlComp
                mainWebView.uiDelegate = self
                mainWebView.navigationDelegate = self
                mainWebView.load(URLRequest(url: url))
            }

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(willEnterForegroundNotification(_:)),
                                                   name: UIApplication.willEnterForegroundNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didEnterBackgroundNotification(_:)),
                                                   name: UIApplication.didEnterBackgroundNotification,
                                                   object: nil)
        }
        isFirstViewAppear = false
    }

    // MARK: - Handlers

    @objc private func willEnterForegroundNotification(_ notification: Notification) {
        if !locationWatchRequestIds.isEmpty {
            startLocationRequest(isOnce: false, isSilent: true)
        }

        if useBeacon {
            beaconWillEnterForeground()
        }

        // If the initial load had already failed at least once when the
        // user backgrounded the app, fire one immediate fresh attempt on
        // resume rather than leaving the splash up indefinitely. The
        // pending backoff was cancelled and the counter zeroed on
        // background entry, so a subsequent failure restarts the
        // sequence from one second.
        if !hasWebReady && hasInitialLoadFailed {
            scheduleImmediateRetry()
        }
    }

    @objc private func didEnterBackgroundNotification(_ notification: Notification) {
        stopLocationRequest()

        if useBeacon {
            beaconDidEnterBackground()
        }

        // iOS suspends the process shortly after backgrounding, so any
        // pending `Task.sleep` would fire at an unpredictable wall-clock
        // moment on resume. Cancel the pending retry and reset the
        // backoff so foreground re-entry can start clean.
        resetRetryState()
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        // Walk the presentation chain so a `present` call always lands on the
        // top-most view controller. This prevents "Attempt to present X on
        // Y while Z is presented" warnings when the SDK shows permission
        // alerts on top of an already-displayed modal.
        guard var front = self.presentedViewController else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
            return
        }

        while true {
            if let frontOfFront = front.presentedViewController {
                front = frontOfFront
            } else {
                break
            }
        }

        front.present(viewControllerToPresent, animated: flag, completion: completion)
    }
}

// MARK: - WKUIDelegate
extension PMMainViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { (_) in
            completionHandler()
        }
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { (_) in
            completionHandler(true)
        }
        alert.addAction(okAction)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            completionHandler(false)
        }
        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
    }
}

// MARK: - WKNavigationDelegate
extension PMMainViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Provisional navigation failures (DNS, TLS, offline, timeout, …)
        // happen *before* the WebView has any document to display. While
        // the web layer has not yet signalled `web.ready` there is no
        // in-page UI to offer the user a retry, so the SDK drives one
        // itself with exponential backoff. Once the web layer is alive it
        // owns navigation, and any subsequent failures are its concern.
        isWebViewLoading = false
        if !hasWebReady {
            scheduleNextRetry()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        // Treat HTTP 4xx / 5xx on the initial main-frame load as a
        // recoverable failure. Without this the WebView would happily
        // render the origin's error page and stay there forever (the
        // server returned a body, so `didFailProvisionalNavigation` does
        // not fire). After `web.ready` has fired we leave HTTP errors to
        // the web layer, which can present a richer in-page response.
        if !hasWebReady,
           navigationResponse.isForMainFrame,
           let httpResponse = navigationResponse.response as? HTTPURLResponse,
           (400...599).contains(httpResponse.statusCode) {
            decisionHandler(.cancel)
            scheduleNextRetry()
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if hasWebReady {
            // Once `web.ready` has fired we trust the web layer to manage
            // subsequent navigations on its own.
            return
        }
        isWebViewLoading = true

        let loadingAt = Date()
        webViewLoadingAt = loadingAt
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isWebViewLoading = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let requestUrl = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            decisionHandler(.cancel)
            return
        }

        if requestUrl.scheme != "command" {
            switch navigationAction.navigationType {
            case .linkActivated:
                // Anchor tap: route HTTPS/HTTP through Safari View Controller
                // (or the delegate), and let the OS resolve recognised
                // schemes like `tel:` / `mailto:`.
                if requestUrl.scheme == "https" || requestUrl.scheme == "http" {
                    openSafariViewController(url)
                } else if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                decisionHandler(.cancel)
                return
            default:
                break
            }
            decisionHandler(.allow)
            return
        }

        // command://* is consumed by the bridge — never let WebKit follow it.
        decisionHandler(.cancel)
        runCommand(commandUrl: requestUrl)
    }
    private func dictionaryFromUrlQuery(url: URLComponents) -> [String: String] {
        guard let queryItems = url.queryItems else {
            return [:]
        }

        var work = [String: String]()
        queryItems.forEach { (item) in
            work[item.name] = item.value ?? ""
        }
        return work
    }
}

// MARK: - Platinumaps Command Interface
extension PMMainViewController {
    private func runCommand(commandUrl: URLComponents) {
        guard let command = PMCommand(rawValue: commandUrl.host ?? "") else {
            return
        }
        let queryItems = dictionaryFromUrlQuery(url: commandUrl)
        guard let requestId = queryItems["requestId"] else {
            return
        }
        switch command {
        case .appInfo:
            var args: [String: Any] = [:]
            if let userId = userId, !userId.isEmpty {
                args["userId"] = userId
            }
            if let secretKey = secretKey, !secretKey.isEmpty {
                args["secretKey"] = secretKey
            }
            args["offsetBottom"] = offsetBottom;
            commandCallback(command, requestId: requestId, args: args)
        case .webReady:
            isWebViewLoading = false
            hasWebReady = true
            // Successful initial load — drop any retry state that may have
            // accumulated from earlier failed attempts.
            resetRetryState()
            clearInitialLoadFailureLatch()
            var args: [String: Any] = [:]
            hideCoverImageView { [weak self] in
                if let url = self?.launchURL {
                    args["launchUrl"] = url.absoluteString
                    self?.launchURL = nil
                }
                self?.commandCallback(command, requestId: requestId, args: args)
            }
            return
        case .webWillReload:
            hasWebReady = false
            // The web layer is dropping its document and re-loading. Treat
            // this like a fresh initial load: clear any retry state so the
            // backoff starts at zero if the upcoming load fails.
            resetRetryState()
            clearInitialLoadFailureLatch()
            showCoverImageView { [weak self] in
                self?.commandCallback(command, requestId: requestId, args: [:])
            }
            return
        case .locationStatus:
            let status = locationAuthorizationStatus()
            locationStatusCommandCallback(status, command: command, requestId: requestId)
            return
        case .locationAuthorize:
            let status = locationAuthorizationStatus()
            if status == .notDetermined {
                locationAuthorizeRequestId = requestId
                locationRequestWhenInUseAuthorization()
            } else {
                locationStatusCommandCallback(status, command: command, requestId: requestId)
            }
            return
        case .beaconAuthorize:
            let status = locationAuthorizationStatus()
            if status == .notDetermined {
                beaconAuthorizeRequestId = requestId
                locationRequestWhenInUseAuthorization()
            } else {
                locationStatusCommandCallback(status, command: command, requestId: requestId)
            }
            return
        case .locationOnce:
            locationOnceRequestIds.append(requestId)
            startLocationRequest(isOnce: true, isSilent: false)
            return
        case .locationWatch:
            locationWatchRequestIds.append(requestId)
            startLocationRequest(isOnce: false, isSilent: false)
            return
        case .locationClearWatch:
            locationWatchRequestIds.removeAll()
            stopLocationRequestIfNoRequest()
            break
        case .beaconOnce:
            logBeacon("command: beacon.once")
            beaconOnceRequestIds.append(requestId)
            startBeaconRequest(isOnce: true, isSilent: false)
            return
        case .beaconWatch:
            logBeacon("command: beacon.watch")
            beaconWatchRequestIds.append(requestId)
            startBeaconRequest(isOnce: false, isSilent: false)
            return
        case .beaconClearWatch:
            logBeacon("command: beacon.clearwatch")
            beaconWatchRequestIds.removeAll()
            stopBeaconRequestIfNoRequest()
            break
        case .stampRallyQrCode:
            break
        case .browseApp, .browseInApp:
            if let target = queryItems["url"] {
                var wUrl = URL(string: target)
                if wUrl?.scheme == nil {
                    // Schemeless URLs (`/foo/bar`) are resolved against the
                    // currently-displayed map origin so the same domain is
                    // preserved.
                    wUrl = URL(string: target, relativeTo: originalUrl.url)?.absoluteURL
                }

                if let url = wUrl, Self.isSchemeAllowedForBrowse(url) {
                    if let _ = delegate {
                        delegate?.openLink(url, sharedCookie: queryItems["sharedCookie"] == "true")
                        return
                    }
                    if command == .browseApp
                        || (url.scheme != "https" && url.scheme != "http") {
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    } else if queryItems["sharedCookie"] == "true" {
                        let vc = PMWebViewController()
                        vc.pageUrl = url
                        let nc = UINavigationController(rootViewController: vc)
                        present(nc, animated: true, completion: nil)
                    } else {
                        openSafariViewController(url)
                    }
                }
            }
            break
        case .appDetect:
            break
        case .appReview:
            if let appId = appStoreId,
               let url = URL(string: "https://itunes.apple.com/app/id\(appId)?action=write-review") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            break
        case .mapNavigate:
            if let target = queryItems["url"], let url = URL(string: target), Self.isSchemeAllowedForBrowse(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            break
        case .searchFocus:
            break
        }
        commandCallback(command, requestId: requestId, args: [:])
    }

    /// True when `url`'s scheme is in the SDK's browse allowlist. Returning
    /// false means the SDK silently drops the navigation request rather than
    /// risk handing arbitrary URLs (`javascript:`, `file:`, `about:`, …) to
    /// `UIApplication.open`.
    private static func isSchemeAllowedForBrowse(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return Self.browseAllowedSchemes.contains(scheme)
    }

    private func commandCallbackAsync(_ command: PMCommand, requestId: String, args: [String: Any], completion: ((Any?, Error?) -> Void)? = nil) {
        // We construct the JS expression by JSON-encoding every input. This
        // prevents the web side (or anyone able to plant a `requestId` value)
        // from breaking out of the string and executing arbitrary JS in our
        // page context.
        guard let commandLiteral = Self.jsLiteral(command.rawValue),
              let requestIdLiteral = Self.jsLiteral(requestId),
              let argsLiteral = Self.jsLiteral(args) else {
            completion?(nil, nil as Error?)
            return
        }
        let script = "commandCallback(\(commandLiteral), \(requestIdLiteral), \(argsLiteral))"
        mainWebView.evaluateJavaScript(script) { value, error in
            completion?(value, error)
        }
    }

    private func commandCallback(_ command: PMCommand, requestId: String, args: [String: Any]) {
        commandCallbackAsync(command, requestId: requestId, args: args)
    }

    /// Serializes any JSON-compatible value to a JavaScript literal string
    /// (e.g. `"abc'def"` becomes `"abc\\u0027def"`). Returns `nil` on
    /// non-serializable inputs, in which case callers should drop the
    /// payload rather than emit unsafe JS.
    fileprivate static func jsLiteral(_ value: Any) -> String? {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            return String(data: data, encoding: .utf8)
        } catch {
            // A serialization failure here means the web side will never
            // receive its reply and the Promise will hang. Log unconditionally
            // so the failure is visible in release builds as well.
            NSLog("PMMainViewController.jsLiteral failed: \(error)")
            return nil
        }
    }

    private func showCoverImageView(_ completion: (() -> Void)? = nil) {
        if let coverImageView = self.coverImageView {
            view.bringSubviewToFront(coverImageView)

            if 0 < coverImageView.alpha {
                completion?()
                return
            }

            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.coverImageView?.alpha = 1.0
            } completion: { finished in
                completion?()
            }
        } else {
            completion?()
        }
    }

    private func hideCoverImageView(_ completion: (() -> Void)? = nil) {
        if let coverImageView = self.coverImageView {
            if coverImageView.alpha != 1 {
                completion?()
                return
            }

            // Enforce a minimum on-screen time for the splash so the cover
            // does not flicker when the map happens to load very quickly.
            let limitSeconds = 1.0
            var delay = Date().timeIntervalSince(loadAt)
            if limitSeconds < delay {
                delay = 0
            } else {
                delay = limitSeconds - delay
            }

            UIView.animate(withDuration: 0.3, delay: delay) { [weak self] in
                self?.coverImageView?.alpha = 0.0
            } completion: { [weak self] finished in
                if let imageView = self?.coverImageView {
                    self?.view.sendSubviewToBack(imageView)
                }
                completion?()
            }
        } else {
            completion?()
        }
    }

    private func openSafariViewController(_ url: URL) {
        if let _ = delegate {
            delegate?.openLink(url, sharedCookie: false)
        } else {
            let vc = SFSafariViewController(url: url)
            present(vc, animated: true, completion: nil)
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension PMMainViewController: @preconcurrency CLLocationManagerDelegate {
    /// Returns the current location authorization status. Updated by the
    /// `locationManagerDidChangeAuthorization(_:)` callback.
    private func locationAuthorizationStatus() -> CLAuthorizationStatus {
        return currentAuthorizationStatus
    }

    /// Collapses the system's 5-value `CLAuthorizationStatus` into the
    /// 3-value vocabulary the web bridge speaks (`notDetermined`,
    /// `authorized`, `denied`).
    private func locationAuthorizationStatusText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .authorizedAlways, .authorizedWhenInUse:
            return "authorized"
        default:
            return "denied"
        }
    }

    /// Debug-only verbose status string.
    private func locationAuthorizationStatusTextFull(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        default: return status.rawValue.description
        }
    }

    /// Sends the authorization status to the web side as a reply to the given
    /// command + requestId.
    private func locationStatusCommandCallback(_ status: CLAuthorizationStatus, command: PMCommand, requestId: String) {
        let statusText = locationAuthorizationStatusText(status)
        commandCallback(command, requestId: requestId, args: ["status": statusText])
    }

    private func startLocationRequest(isOnce: Bool, isSilent: Bool) {
        let status = locationAuthorizationStatus()

        switch status {
        case .notDetermined:
            locationRequestWhenInUseAuthorization()
            return
        case .restricted:
            if !isSilent {
                presentAlertForLocationRestricted()
            }
            locationCommandCallback(location: nil, heading: nil)
            return
        case .denied:
            if !isSilent {
                presentAlertForLocationDenied()
            } else {
                locationCommandCallback(location: nil, heading: nil)
            }
            return
        case .authorizedAlways, .authorizedWhenInUse:
            if isMeasuringLocation {
                if isOnce {
                    // Force a one-shot fix even though we are already
                    // watching, so the `location.once` caller gets a fast
                    // response without waiting for the next watch tick.
                    locationManager.requestLocation()
                }
                return
            }
            locationCallbackStatus = 0
            lastHeading = nil

            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            locationManager.startMonitoringSignificantLocationChanges()
            isMeasuringLocation = true
            return
        @unknown default:
            locationCommandCallback(location: nil, heading: nil)
            return
        }
    }

    private func locationRequestWhenInUseAuthorization() {
        // Defer to the next run-loop tick: calling
        // `requestWhenInUseAuthorization()` from inside a
        // `WKNavigationDelegate` callback can prevent the system permission
        // dialog from appearing.
        Task {
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    private func localizedString(forKey key: String) -> String {
        return NSLocalizedString(key, bundle: bundle, comment: "");
    }

    /// Shows the "permission denied" alert. The OK action deep-links into
    /// the system Settings app.
    private func presentAlertForLocationDenied() {
        if isAlertPresentedForLocationDenied {
            return
        }
        isAlertPresentedForLocationDenied = true

        let alertTitle = localizedString(forKey: "PMDeniedTitle")
        let alertMessage = localizedString(forKey: "PMDeniedMessage")
        let okTitle = localizedString(forKey: "PMDeniedOk")
        let cancelTitle = localizedString(forKey: "PMDeniedCancel")

        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)

        let okAction = UIAlertAction(title: okTitle, style: .default) { [weak self] _ in
            self?.isAlertPresentedForLocationDenied = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        alert.addAction(okAction)

        let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { [weak self] _ in
            self?.isAlertPresentedForLocationDenied = false
            self?.locationCommandCallback(location: nil, heading: nil)
        }
        alert.addAction(cancelAction)

        present(alert, animated: true, completion: nil)
    }

    /// Variant of `presentAlertForLocationDenied` that resolves the in-flight
    /// beacon command with `hasError: true` on cancel.
    private func presentAlertForLocationDeniedForBeacon() {
        if isAlertPresentedForLocationDenied {
            return
        }
        isAlertPresentedForLocationDenied = true

        let alertTitle = localizedString(forKey: "PMDeniedTitle")
        let alertMessage = localizedString(forKey: "PMDeniedMessage")
        let okTitle = localizedString(forKey: "PMDeniedOk")
        let cancelTitle = localizedString(forKey: "PMDeniedCancel")

        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)

        let okAction = UIAlertAction(title: okTitle, style: .default) { [weak self] _ in
            self?.isAlertPresentedForLocationDenied = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        alert.addAction(okAction)

        let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { [weak self] _ in
            self?.isAlertPresentedForLocationDenied = false
            self?.beaconCommandCallback(beacons: nil, hasError: true)
        }
        alert.addAction(cancelAction)

        present(alert, animated: true, completion: nil)
    }

    /// Shows the "Location Services restricted" alert (parental controls,
    /// MDM, etc.). The user cannot fix this in-app, so the alert only has an
    /// OK acknowledgement.
    private func presentAlertForLocationRestricted() {
        if isAlertPresentedForLocationRestricted {
            return
        }
        isAlertPresentedForLocationRestricted = true

        let alertTitle = localizedString(forKey: "PMRestrictedTitle")
        let alertMessage = localizedString(forKey: "PMRestrictedMessage")

        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)

        let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.isAlertPresentedForLocationRestricted = false
        }
        alert.addAction(okAction)

        present(alert, animated: true, completion: nil)
    }

    private func stopLocationRequestIfNoRequest() {
        if locationOnceRequestIds.isEmpty && locationWatchRequestIds.isEmpty {
            stopLocationRequest()
        }
    }

    private func stopLocationRequest() {
        guard isMeasuringLocation else {
            return
        }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        locationManager.stopMonitoringSignificantLocationChanges()
        isMeasuringLocation = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        self.currentAuthorizationStatus = status

        if !locationOnceRequestIds.isEmpty || !locationWatchRequestIds.isEmpty {
            // A location command is in flight — kick off measurement now
            // that we know whether we are allowed to.
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                startLocationRequest(isOnce: !locationWatchRequestIds.isEmpty, isSilent: true)
            case .notDetermined:
                break
            default:
                stopLocationRequest()
                locationCommandCallback(location: nil, heading: nil)
                locationWatchRequestIds.removeAll()
            }
        }

        //#region Beacon
        if !beaconOnceRequestIds.isEmpty || !beaconWatchRequestIds.isEmpty {
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                startMonitoringBeaconIfNeeded()
                break
            case .notDetermined:
                break
            default: // denied, restricted
                stopRangingBeaconsIfNeeded()
                stopMonitoringBeaconIfNeeded()
                beaconCommandCallback(beacons: nil, hasError: true)
            }
        }
        //#endregion

        if status != .notDetermined {
            // The first authorization callback after construction is always
            // `.notDetermined`; skip that one so we only reply to the web on
            // a real decision.
            if let requestId = locationAuthorizeRequestId {
                locationStatusCommandCallback(status, command: .locationAuthorize, requestId: requestId)
                locationAuthorizeRequestId = nil
            }
            if let requestId = beaconAuthorizeRequestId {
                locationStatusCommandCallback(status, command: .beaconAuthorize, requestId: requestId)
                beaconAuthorizeRequestId = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if locationCallbackStatus == 0 {
            locationCallbackStatus = 1
            // `didUpdateLocations` fires before `didUpdateHeading` on the
            // first cycle, so we briefly wait for the heading sample before
            // delivering the very first callback to the web.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                let location = self?.locationManager.location
                let heading = self?.locationManager.heading ?? self?.lastHeading
                self?.locationCommandCallback(location: location, heading: heading)
                self?.locationCallbackStatus = 2
            }
        } else if locationCallbackStatus == 2 {
            // Drop callbacks until the first one has been delivered.
            let location = manager.location
            let heading = manager.heading ?? lastHeading
            locationCommandCallback(location: location, heading: heading)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Cache the latest heading because `manager.heading` can momentarily
        // return `nil` after the first delivery, and `didUpdateLocations`
        // wants something to fall back on.
        lastHeading = newHeading
        if locationCallbackStatus == 2 {
            let location = manager.location
            let heading = newHeading
            locationCommandCallback(location: location, heading: heading)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        stopLocationRequest()
        locationCommandCallback(location: nil, heading: nil, hasError: true)
        locationWatchRequestIds.removeAll()
    }

    private func locationCommandCallback(location: CLLocation?, heading: CLHeading?, hasError: Bool = false) {
        var args: [String: Any] = [:]
        if let location = location {
            // JSONSerialization throws on NaN / Infinity, which would cause
            // `commandCallbackAsync` to drop the reply and leave the web side
            // waiting forever. Filter to finite values so degenerate samples
            // never reach the bridge.
            let lat = location.coordinate.latitude
            let lng = location.coordinate.longitude
            if lat.isFinite && lng.isFinite {
                args["lat"] = lat
                args["lng"] = lng
            }
        }
        if let heading = heading {
            // `magneticHeading` is `-1` while the sensor is calibrating and
            // can be NaN on simulators. Only forward valid samples.
            let magneticHeading = heading.magneticHeading
            if magneticHeading.isFinite && magneticHeading >= 0 {
                args["heading"] = magneticHeading
            }
        }
        if hasError {
            args["hasError"] = true
        }

        let status = locationAuthorizationStatus()
        args["status"] = locationAuthorizationStatusText(status)

        locationOnceRequestIds.forEach { id in
            commandCallback(.locationOnce, requestId: id, args: args)
        }

        locationWatchRequestIds.forEach { id in
            commandCallback(.locationWatch, requestId: id, args: args)
        }

        locationOnceRequestIds.removeAll()
        stopLocationRequestIfNoRequest()
    }
}

// MARK: - Push
extension PMMainViewController {

    /// Forwards a URL (typically captured from a Universal Link / Custom URL
    /// Scheme launch) to the web layer. If the web layer is not yet ready,
    /// the URL is stashed in `launchURL` and replayed once `web.ready`
    /// arrives.
    func pushLaunchURL(_ url: URL) {
        guard hasWebReady else {
            self.launchURL = url
            return
        }

        let commandPushAction: () -> Void = { [weak self] in
            self?.commandPush("app.link", args: ["url": url.absoluteString])
        }

        if presentedViewController == nil {
            // No modal stacked on top — push immediately.
            commandPushAction()
            return
        }

        // Dismiss any presented modals before pushing so the user lands back
        // on the map.
        dismiss(animated: true) {
            commandPushAction()
        }
    }

    /// Sends an unsolicited command to the web side.
    private func commandPush(_ command: String, args: [String: Any]) {
        guard let commandLiteral = Self.jsLiteral(command),
              let argsLiteral = Self.jsLiteral(args) else {
            return
        }
        let script = "commandPush(\(commandLiteral), \(argsLiteral))"
        mainWebView.evaluateJavaScript(script, completionHandler: nil)
    }
}

// MARK: - Beacon
extension PMMainViewController {

    /// Validates the configured UUID and initialises `beaconRegion`. When the
    /// UUID is missing or unparseable beacons are silently disabled and all
    /// `beacon.*` commands become no-ops.
    private func initBeaconIfNeeded() {
        guard let beaconUuid = beaconUuid,
              let uuid = UUID.init(uuidString: beaconUuid) else {
            useBeacon = false
            logBeacon("beacon is disabled: beaconUuid is not given")
            return
        }
        beaconRegion = CLBeaconRegion(uuid: uuid, identifier: "Platinumaps")
        useBeacon = true
        logBeacon("beacon is enabled: region=\(beaconRegion!)")
    }

    /// Entry point for `beacon.once` / `beacon.watch`. Resolves the location
    /// permission and either kicks off monitoring or surfaces an alert.
    private func startBeaconRequest(isOnce: Bool, isSilent: Bool) {
        let status = locationAuthorizationStatus()
        logBeacon("startBeaconRequest(\(isOnce)): authorization status = \(locationAuthorizationStatusTextFull(status))")

        switch status {
        case .notDetermined:
            locationRequestWhenInUseAuthorization()
            return
        case .restricted:
            // Parental Control, MDM, etc.
            if !isSilent {
                presentAlertForLocationRestricted()
            }
            beaconCommandCallback(beacons: nil, hasError: true)
            return
        case .denied:
            if !isSilent {
                presentAlertForLocationDeniedForBeacon()
            } else {
                beaconCommandCallback(beacons: nil, hasError: true)
            }
            return
        case .authorizedAlways, .authorizedWhenInUse:
            startMonitoringBeaconIfNeeded()
            return
        @unknown default:
            // Forward-compat: treat any new authorization state as an error.
            beaconCommandCallback(beacons: nil, hasError: true)
            return
        }
    }

    private func startMonitoringBeaconIfNeeded() {
        guard useBeacon == true else {
            return
        }
        if !isMonitoringBeacon {
            isMonitoringBeacon = true
            locationManager.startMonitoring(for: beaconRegion)
            logBeacon("startMonitoringBeaconIfNeeded: beacon monitoring is started")
        }
    }

    private func stopMonitoringBeaconIfNeeded() {
        guard useBeacon == true else {
            return
        }
        if isMonitoringBeacon {
            isMonitoringBeacon = false
            locationManager.stopMonitoring(for: self.beaconRegion)
            logBeacon("stopMonitoringBeaconIfNeeded: beacon monitoring is stopped")
        }
    }

    /// Stops monitoring once all `beacon.once` / `beacon.watch` callers have
    /// been satisfied.
    private func stopBeaconRequestIfNoRequest() {
        guard useBeacon == true else {
            return
        }
        if beaconOnceRequestIds.isEmpty && beaconWatchRequestIds.isEmpty {
            stopRangingBeaconsIfNeeded()
            stopMonitoringBeaconIfNeeded()
        }
    }

    /// CoreLocation reports that beacon monitoring started — query the
    /// current region state so we can begin ranging immediately when we are
    /// already inside the region.
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard useBeacon == true,
              let beaconRegion = self.beaconRegion else {
            return
        }
        logBeacon("fucn: didStartMonitoringFor")
        self.locationManager.requestState(for: beaconRegion)
    }

    /// Region state resolved — start ranging if we are inside.
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for inRegion: CLRegion) {
        guard useBeacon == true else {
            return
        }
        logBeacon("func: didDetermineState: state = \(state)")
        switch (state) {
        case .inside:
            startRangingBeaconsIfNeeded()
            break
        case .outside:
            break
        case .unknown:
            break
        }
    }

    private func startRangingBeaconsIfNeeded() {
        if !isRangingBeacon {
            self.locationManager.startRangingBeacons(satisfying: self.beaconRegion.beaconIdentityConstraint)
            isRangingBeacon = true
            logBeacon("beacon ranging is now started")
        }
    }

    /// Entered the configured region — begin ranging.
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard useBeacon == true else {
            return
        }
        logBeacon("func: didEnterRegion")
        startRangingBeaconsIfNeeded()
    }

    /// Left the region — stop ranging until we re-enter.
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard useBeacon == true else {
            return
        }
        logBeacon("func: didExitRegion")
        stopRangingBeaconsIfNeeded()
    }

    private func stopRangingBeaconsIfNeeded() {
        guard useBeacon == true else {
            return
        }
        if isRangingBeacon {
            self.locationManager.stopRangingBeacons(satisfying: self.beaconRegion.beaconIdentityConstraint)
            isRangingBeacon = false
            logBeacon("beacon ranging is now stopped")
        }
    }

    /// Ranged beacons — forward to the web side.
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion){
        guard isRangingBeacon && isMonitoringBeacon else {
            // Stragglers after `stopRanging*` was called — drop.
            return
        }

#if DEBUG
        // Ranging callbacks fire frequently; only log in DEBUG builds.
        logBeacon("func: didRangeBeacons")
        for beacon in beacons {
            logBeacon("major:\(beacon.major) minor:\(beacon.minor) rssi:\(beacon.rssi) timestamp:\(beacon.timestamp) accuracy:\(beacon.accuracy)")
        }
#endif

        beaconCommandCallback(beacons: beacons, hasError: false)
    }

    /// Pushes a beacon snapshot (or an error frame) to every in-flight
    /// `beacon.once` / `beacon.watch` requester.
    private func beaconCommandCallback(beacons: [CLBeacon]?, hasError: Bool = false) {
        var args: [String: Any] = [:];

        // Success: ranged beacons available.
        if let beacons = beacons {
            var beaconsArray = [[String: Any]]()
            for beacon in beacons {
                // `accuracy > 0` excludes the documented `-1` (unknown) and
                // NaN values, but `isFinite` also rejects `+Infinity` so the
                // payload is always JSON-serializable.
                if beacon.accuracy > 0 && beacon.accuracy.isFinite {
                    beaconsArray.append([
                        "uuid": beacon.uuid.uuidString,
                        "major": beacon.major,
                        "minor": beacon.minor,
                        "rssi": beacon.rssi,
                        "timestamp": Int64(beacon.timestamp.timeIntervalSince1970 * 1000),
                        "accuracy": beacon.accuracy,
                        "proximity": beacon.proximity.rawValue
                    ])
                }
            }
            args["beacons"] = beaconsArray
            _beaconCommandCallback(args: args)
            return
        }

        guard hasError else {
            args["beacons"] = [[String: Any]]()
            _beaconCommandCallback(args: args)
            return
        }

        // Error path: tell the web side what went wrong and clear watchers
        // so they do not block subsequent requests.
        args["hasError"] = true

        let status = locationAuthorizationStatus()
        args["status"] = locationAuthorizationStatusText(status)

        _beaconCommandCallback(args: args)

        beaconWatchRequestIds.removeAll()
    }

    private func _beaconCommandCallback(args: [String: Any]) {
        beaconOnceRequestIds.forEach { id in
            commandCallback(.beaconOnce, requestId: id, args: args)
        }

        beaconWatchRequestIds.forEach { id in
            commandCallback(.beaconWatch, requestId: id, args: args)
        }

        beaconOnceRequestIds.removeAll()
        stopBeaconRequestIfNoRequest()
    }

    private func beaconDidEnterBackground() {
        if isRangingBeacon || isMonitoringBeacon {
            isBeaconPaused = true
            stopRangingBeaconsIfNeeded()
            stopMonitoringBeaconIfNeeded()
            logBeacon("beacon monitoring/ranging is paused when in background")
        }
    }

    private func beaconWillEnterForeground() {
        if isBeaconPaused {
            logBeacon("resuming beacon monitoring/ranging")
            isBeaconPaused = false
        }

        // Two distinct foreground paths land here:
        //   1. We were already ranging when the app backgrounded.
        //   2. The user was sent to Settings to change permission and is now
        //      coming back, with or without granting.
        if !beaconWatchRequestIds.isEmpty {
            startBeaconRequest(isOnce: false, isSilent: true)
        } else if !beaconOnceRequestIds.isEmpty {
            startBeaconRequest(isOnce: true, isSilent: true)
        }
    }

    private func logBeacon(_ text: String) -> Void {
#if DEBUG
        print("[Beacon] \(text)")
#endif
    }
}

// MARK: - Initial-Load Retry
//
// The SDK retries the initial map URL when it fails to load, because there
// is no web-side retry UI for the document that hosts it: a transient DNS
// hiccup, a 5xx from the origin, or the user briefly losing connectivity
// would otherwise leave the splash screen on indefinitely. The retry loop
// is intentionally narrow:
//
//   * Only the *initial* load is monitored. Once `web.ready` fires the web
//     layer owns the navigation and the SDK steps out of the way.
//   * Retries continue forever while the controller is foregrounded. The
//     backoff caps at `maxRetryDelaySeconds`, so the load is reattempted
//     at most every few seconds.
//   * Entering the background cancels any pending retry and resets the
//     backoff so foreground re-entry feels like a fresh start.
extension PMMainViewController {
    /// Upper bound (in seconds) on the wait between retries. The backoff
    /// is `min(2^attempt, maxRetryDelaySeconds)`, so the sequence is
    /// `1, 2, 4, 8, 8, 8, …`. A user staring at the splash is unlikely to
    /// tolerate longer waits, and longer waits do not meaningfully reduce
    /// origin load for a single client.
    private static let maxRetryDelaySeconds: Double = 8

    /// Unified logger for the initial-load retry path. Routed through
    /// `os.Logger` so messages can be filtered by subsystem and category
    /// in Console.app and `log show`, and so debug-level entries are
    /// elided from release builds without an explicit `#if DEBUG` guard.
    private static let retryLog = Logger(
        subsystem: "jp.co.boldright.platinumaps.sdk",
        category: "retry"
    )

    /// Schedules the next retry of the initial map URL using exponential
    /// backoff. Any retry already in flight is cancelled and replaced.
    /// The attempt counter is advanced so successive failures wait longer
    /// up to `maxRetryDelaySeconds`. Also latches `hasInitialLoadFailed`,
    /// which the foreground-recovery path consults after the counter has
    /// been zeroed by `resetRetryState()`.
    fileprivate func scheduleNextRetry() {
        hasInitialLoadFailed = true
        let attempt = retryAttempt
        retryAttempt = attempt + 1
        let delay = min(pow(2.0, Double(attempt)), Self.maxRetryDelaySeconds)
        Self.retryLog.debug("scheduleNextRetry: attempt=\(attempt) delay=\(delay)s")
        scheduleRetry(after: delay)
    }

    /// Schedules an immediate retry without advancing the backoff counter.
    /// Used on foreground re-entry: if the load was still failing when the
    /// user backgrounded the app, we want them to see one immediate fresh
    /// attempt before any wait kicks in.
    fileprivate func scheduleImmediateRetry() {
        Self.retryLog.debug("scheduleImmediateRetry")
        scheduleRetry(after: 0)
    }

    private func scheduleRetry(after delaySeconds: Double) {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            if delaySeconds > 0 {
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            guard let self, !Task.isCancelled, !self.hasWebReady else {
                return
            }
            Self.retryLog.debug("firing retry: reloading initial URL")
            self.loadInitialURLForRetry()
        }
    }

    /// Cancels any pending retry without touching the attempt counter, so
    /// a subsequent `scheduleNextRetry()` resumes the backoff where it
    /// left off.
    fileprivate func cancelPendingRetry() {
        if retryTask != nil {
            Self.retryLog.debug("cancelPendingRetry")
        }
        retryTask?.cancel()
        retryTask = nil
    }

    /// Cancels any pending retry and resets the attempt counter. The
    /// `hasInitialLoadFailed` latch is only cleared by the success paths
    /// (`web.ready`, `web.willreload`); see `clearInitialLoadFailureLatch()`.
    /// Called on `web.ready`, on `web.willreload`, and when the app
    /// enters the background.
    fileprivate func resetRetryState() {
        cancelPendingRetry()
        retryAttempt = 0
    }

    /// Clears the `hasInitialLoadFailed` latch. Separated from
    /// `resetRetryState()` so the background path can wipe pending work
    /// without telling foreground recovery that the load has succeeded.
    fileprivate func clearInitialLoadFailureLatch() {
        if hasInitialLoadFailed {
            Self.retryLog.debug("clearInitialLoadFailureLatch: initial load now considered successful")
        }
        hasInitialLoadFailed = false
    }

    /// Re-issues the initial map URL. Not to be confused with
    /// `reloadWebView(_:)`, which is a navigation-stack reset used while
    /// the page is already live; this method is for the case where the
    /// initial load itself never completed.
    private func loadInitialURLForRetry() {
        guard let url = originalUrl.url else {
            return
        }
        // Keep the splash visible so the user never glimpses an empty
        // WKWebView between attempts.
        showCoverImageView()
        isWebViewLoading = true
        mainWebView.load(URLRequest(url: url))
    }
}
