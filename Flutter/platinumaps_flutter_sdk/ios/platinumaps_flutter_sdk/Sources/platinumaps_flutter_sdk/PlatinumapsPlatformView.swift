import Flutter
import UIKit

/// Hosts a `PMMapView` inside a Flutter PlatformView and bridges the
/// `PMMapViewDelegate.openLink` callback through a per-instance
/// `FlutterMethodChannel`.
///
/// PlatformView callbacks (`view()`, `init(frame:viewIdentifier:…)`,
/// `applyCreationArguments`) are invoked on the main thread by
/// Flutter; mark the class `@MainActor` so the Swift 6 strict
/// concurrency checker can see that.
@MainActor
final class PlatinumapsPlatformView: NSObject, FlutterPlatformView, PMMapViewDelegate {

    /// URL schemes the plugin will forward to `PMMapView.launchURL`.
    /// Matches the SDK's `browseAllowedSchemes` so the same
    /// allowlist applies to host-supplied launch URLs.
    private static let allowedLaunchUrlSchemes: Set<String> = [
        "http", "https", "tel", "mailto", "sms", "geo",
    ]

    private let mapView: PMMapView
    private let methodChannel: FlutterMethodChannel

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: [String: Any]?,
        messenger: FlutterBinaryMessenger
    ) {
        let mv = PMMapView(frame: frame)
        Self.applyCreationArguments(args, to: mv)

        self.mapView = mv
        self.methodChannel = FlutterMethodChannel(
            name: "\(PlatinumapsFlutterPlugin.viewType)/\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        // Only claim PMMapViewDelegate when the Dart side actually has
        // an `onOpenLink` handler. Setting the delegate unconditionally
        // would suppress PMMapView's default link handling
        // (`SFSafariViewController` for HTTPS, `UIApplication.open` for
        // other allowlisted schemes), causing every browse.* / map.navigate
        // link to be silently dropped when the host did not supply a
        // callback.
        if args?["hasOpenLinkHandler"] as? Bool == true {
            mv.delegate = self
        }
    }

    deinit {
        // Sever the delegate link before tearing down so an in-flight
        // PMMapView callback cannot fire into a deallocated wrapper.
        // PMMapView holds the delegate weakly, but clearing it is the
        // mirror of the Android plugin's `webView.onOpenLinkListener =
        // null` in dispose(). UIView deinit runs on the main thread,
        // so we assume the main-actor isolation rather than hop —
        // same pattern PMMapView uses for its own deinit cleanup.
        MainActor.assumeIsolated {
            mapView.delegate = nil
        }
    }

    /// Maps the platform-channel creation-args dictionary onto a
    /// `PMMapView`'s public properties. Pulled out of `init` so unit
    /// tests can exercise the field-by-field translation directly,
    /// without standing up a `FlutterMethodChannel`.
    ///
    /// `coverImage` is intentionally not handled. The Dart side
    /// declines to serialize `ImageProvider` across the platform
    /// channel — no key is emitted by `_creationParams` — so the
    /// argument never reaches this method in v0.1. The parameter is
    /// kept on the Dart public API for forward compatibility;
    /// `Flutter/DESIGN.md` §8 #5 tracks the parity follow-up that
    /// will plumb it through.
    @MainActor
    internal static func applyCreationArguments(
        _ args: [String: Any]?,
        to mapView: PMMapView
    ) {
        // The Dart side sends `mapSlug` because that name matches the
        // existing iOS SDK; the Android side maps it to `mapPath`.
        mapView.mapSlug = args?["mapSlug"] as? String

        if let queryParams = args?["queryParams"] as? [String: String] {
            mapView.mapQuery = queryParams
        }
        if let localeCode = args?["locale"] as? String,
           let locale = PMLocale(rawValue: localeCode) {
            mapView.mapLocale = locale
        }
        if let appStoreId = args?["appStoreId"] as? String {
            mapView.appStoreId = appStoreId
        }
        if let userId = args?["userId"] as? String {
            mapView.userId = userId
        }
        if let secretKey = args?["secretKey"] as? String {
            mapView.secretKey = secretKey
        }
        if let offsetBottom = args?["offsetBottom"] as? Int {
            mapView.offsetBottom = offsetBottom
        }
        if let beacon = args?["beacon"] as? [String: Any] {
            if let uuid = beacon["uuid"] as? String {
                mapView.beaconUuid = uuid
            }
            // Match the wire format the native Android SDK uses: it
            // appends `beaconminsample` / `beaconmaxhistory` / `memo`
            // URL query parameters during `openPlatinumaps`. iOS
            // PMMapView has no public API for these optional fields,
            // so fold them into `mapQuery` so the same parameters
            // reach the web layer regardless of platform.
            var extras = mapView.mapQuery
            if let minSample = beacon["minSample"] as? Int {
                extras["beaconminsample"] = String(minSample)
            }
            if let maxHistory = beacon["maxHistory"] as? Int {
                extras["beaconmaxhistory"] = String(maxHistory)
            }
            if let memo = beacon["memo"] as? String {
                extras["memo"] = memo
            }
            mapView.mapQuery = extras
        }
        if let launchUrlString = args?["launchUrl"] as? String,
           let launchUrl = Self.parseLaunchUrl(launchUrlString),
           Self.allowedLaunchUrlSchemes.contains(launchUrl.scheme?.lowercased() ?? "") {
            // The web layer eventually echoes `launchUrl` back through
            // its own command flow, so the Flutter host can stage a
            // `javascript:` or `intent:`-style URL via the Dart API
            // and reach the inside of the PlatformView's WebView.
            // Mirror the SDK's `browseAllowedSchemes` allowlist here
            // so the same defence-in-depth applies to host-supplied
            // launch URLs.
            mapView.launchURL = launchUrl
        }
    }

    func view() -> UIView {
        return mapView
    }

    /// Parse a `launchUrl` string into a `URL`.
    ///
    /// On iOS 17+ the default `URL(string:)` silently percent-encodes
    /// invalid characters, which can turn a malformed Dart-side string
    /// into a "valid" URL. The `encodingInvalidCharacters: false`
    /// overload (also iOS 17+) refuses the input instead — which is
    /// what we want, since the Dart side already typed the value as
    /// `Uri`. On iOS 16 we fall back to the older, lenient behaviour.
    private static func parseLaunchUrl(_ string: String) -> URL? {
        if #available(iOS 17.0, *) {
            return URL(string: string, encodingInvalidCharacters: false)
        }
        return URL(string: string)
    }

    // MARK: - PMMapViewDelegate

    func openLink(_ url: URL, sharedCookie: Bool) {
        methodChannel.invokeMethod(
            "onOpenLink",
            arguments: [
                "url": url.absoluteString,
                "sharedCookie": sharedCookie,
            ]
        )
    }
}
