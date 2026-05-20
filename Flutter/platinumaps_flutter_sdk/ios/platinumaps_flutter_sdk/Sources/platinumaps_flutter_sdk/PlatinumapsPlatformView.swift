import Flutter
import UIKit

/// Hosts a `PMMapView` inside a Flutter PlatformView and bridges the
/// `PMMapViewDelegate.openLink` callback through a per-instance
/// `FlutterMethodChannel`.
final class PlatinumapsPlatformView: NSObject, FlutterPlatformView, PMMapViewDelegate {

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
        mv.delegate = self
    }

    /// Maps the platform-channel creation-args dictionary onto a
    /// `PMMapView`'s public properties. Pulled out of `init` so unit
    /// tests can exercise the field-by-field translation directly,
    /// without standing up a `FlutterMethodChannel`.
    ///
    /// `coverImage` is intentionally not handled: the Dart side ships
    /// an opaque `ImageProvider` that has no stable wire
    /// representation (tracked in `Flutter/DESIGN.md` §8 #5).
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
        if let beacon = args?["beacon"] as? [String: Any],
           let uuid = beacon["uuid"] as? String {
            mapView.beaconUuid = uuid
        }
        if let launchUrlString = args?["launchUrl"] as? String,
           let launchUrl = URL(string: launchUrlString) {
            mapView.launchURL = launchUrl
        }
    }

    func view() -> UIView {
        return mapView
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
