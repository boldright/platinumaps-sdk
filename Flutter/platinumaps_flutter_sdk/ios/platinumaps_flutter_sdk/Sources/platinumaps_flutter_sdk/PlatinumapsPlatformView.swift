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

    /// `true` when [url]'s scheme is in the launch-URL allowlist.
    /// Exposed at static scope so unit tests can pin the allowlist
    /// behaviour directly.
    internal static func isAllowedLaunchUrlScheme(_ url: URL) -> Bool {
        return Self.allowedLaunchUrlSchemes.contains(
            url.scheme?.lowercased() ?? ""
        )
    }

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

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    deinit {
        // Sever the delegate link and tear down the method-channel
        // handler before deallocation so in-flight callbacks cannot
        // fire into a deallocated wrapper. UIView deinit runs on the
        // main thread, so assume main-actor isolation rather than hop.
        MainActor.assumeIsolated {
            mapView.delegate = nil
            methodChannel.setMethodCallHandler(nil)
        }
    }

    /// Handles Dart → native invocations coming from
    /// `PlatinumapsMapController`.
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pushLaunchUrl":
            guard let args = call.arguments as? [String: Any],
                  let urlString = args["url"] as? String,
                  let url = Self.parseLaunchUrl(urlString),
                  Self.isAllowedLaunchUrlScheme(url) else {
                result(FlutterError(
                    code: "invalid_arguments",
                    message: "pushLaunchUrl requires a `url` with an allowlisted scheme",
                    details: nil
                ))
                return
            }
            mapView.pushLaunchURL(url)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Maps the platform-channel creation-args dictionary onto a
    /// `PMMapView`'s public properties. Pulled out of `init` so unit
    /// tests can exercise the field-by-field translation directly,
    /// without standing up a `FlutterMethodChannel`.
    @MainActor
    internal static func applyCreationArguments(
        _ args: [String: Any]?,
        to mapView: PMMapView
    ) {
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
            // its own command flow, so without an allowlist a Flutter
            // host could stage a `javascript:` or `data:`-style URL
            // via the Dart API and reach the inside of the
            // PlatformView's WebView. Mirror the SDK's
            // `browseAllowedSchemes` allowlist here so the same
            // defence-in-depth applies to host-supplied launch URLs.
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
