import UIKit

/// Backwards-compatible alias for the renamed `PMMapViewDelegate`. Existing
/// host applications that adopt `PMMainViewControllerDelegate` continue to
/// compile unchanged.
public typealias PMMainViewControllerDelegate = PMMapViewDelegate

/// Thin `UIViewController` wrapper around `PMMapView`, preserved as the
/// documented entry point for native iOS integrators. All bridge / WebView /
/// sensor logic lives on the embedded `PMMapView`; this controller exists so
/// existing host apps that follow `iOS/README.md` keep working with no
/// source-level changes.
///
/// New Flutter / SwiftUI integrators should reach for `PMMapView` directly.
public class PMMainViewController: UIViewController {

    /// The underlying view that owns all SDK state.
    public let mapView = PMMapView(frame: .zero)

    public weak var delegate: PMMainViewControllerDelegate? {
        get { mapView.delegate }
        set { mapView.delegate = newValue }
    }

    /// Required. The URL-safe slug of the map to display. The final URL is
    /// `https://platinumaps.jp/maps/<mapSlug>`.
    public var mapSlug: String? {
        get { mapView.mapSlug }
        set { mapView.mapSlug = newValue }
    }

    /// Optional. Extra query parameters appended to the map URL.
    public var mapQuery: [String: String] {
        get { mapView.mapQuery }
        set { mapView.mapQuery = newValue }
    }

    /// Optional. Forces the map UI language. When `nil` the WebView's
    /// `Accept-Language` (derived from `UserDefaults.standard`'s
    /// `AppleLanguages`) determines the language.
    public var mapLocale: PMLocale? {
        get { mapView.mapLocale }
        set { mapView.mapLocale = newValue }
    }

    /// Optional. The numeric App Store ID (e.g. `"1234567890"`) used by the
    /// `app.review` command to open the App Store review page.
    public var appStoreId: String? {
        get { mapView.appStoreId }
        set { mapView.appStoreId = newValue }
    }

    /// Optional. Splash image shown while the web layer boots; faded out once
    /// the web layer signals `web.ready`.
    public var coverImage: UIImage? {
        get { mapView.coverImage }
        set { mapView.coverImage = newValue }
    }

    /// Optional. Opaque user identifier the web app may consume via
    /// `app.info`.
    public var userId: String? {
        get { mapView.userId }
        set { mapView.userId = newValue }
    }

    /// Optional. Opaque shared secret the web app may consume via `app.info`.
    /// Treat this as sensitive: only set it when the host application has a
    /// legitimate need for the web layer to authenticate the user.
    public var secretKey: String? {
        get { mapView.secretKey }
        set { mapView.secretKey = newValue }
    }

    /// Optional. When non-zero, the SDK reports `safearea` to the web with
    /// the bottom inset zeroed out — useful when the host already adds its
    /// own bottom inset (e.g. a tab bar).
    public var offsetBottom: Int {
        get { mapView.offsetBottom }
        set { mapView.offsetBottom = newValue }
    }

    /// Optional override for the top safe-area inset forwarded to the
    /// web layer. See `PMMapView.safeAreaTopOverride`.
    public var safeAreaTopOverride: Int? {
        get { mapView.safeAreaTopOverride }
        set { mapView.safeAreaTopOverride = newValue }
    }

    /// Companion to [safeAreaTopOverride] for the bottom inset.
    public var safeAreaBottomOverride: Int? {
        get { mapView.safeAreaBottomOverride }
        set { mapView.safeAreaBottomOverride = newValue }
    }

    /// Optional. URL captured from a Universal Link / Custom URL Scheme launch
    /// that should be forwarded to the web app once it is ready. Use
    /// `pushLaunchURL(_:)` from outside the SDK to push a URL at runtime.
    public var launchURL: URL? {
        get { mapView.launchURL }
        set { mapView.launchURL = newValue }
    }

    /// Optional. iBeacon UUID (hyphenated) to range. When `nil` the beacon
    /// path is disabled and `beacon.*` commands resolve as no-ops.
    public var beaconUuid: String? {
        get { mapView.beaconUuid }
        set { mapView.beaconUuid = newValue }
    }

    /// Enable WebKit Inspector (`isInspectable` on iOS 16.4+) for the
    /// embedded `WKWebView`. Off by default.
    public var isWebViewInspectable: Bool {
        get { mapView.isWebViewInspectable }
        set { mapView.isWebViewInspectable = newValue }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// Forwards a URL (typically captured from a Universal Link / Custom URL
    /// Scheme launch) to the web layer. If the web layer is not yet ready,
    /// the URL is stashed in `launchURL` and replayed once `web.ready`
    /// arrives.
    public func pushLaunchURL(_ url: URL) {
        mapView.pushLaunchURL(url)
    }
}
