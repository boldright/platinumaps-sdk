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

        // The Dart side sends `mapSlug` because that name matches the
        // existing iOS SDK; the Android side maps it to `mapPath`.
        mv.mapSlug = args?["mapSlug"] as? String

        if let queryParams = args?["queryParams"] as? [String: String] {
            mv.mapQuery = queryParams
        }
        if let localeCode = args?["locale"] as? String,
           let locale = PMLocale(rawValue: localeCode) {
            mv.mapLocale = locale
        }
        if let appStoreId = args?["appStoreId"] as? String {
            mv.appStoreId = appStoreId
        }
        if let userId = args?["userId"] as? String {
            mv.userId = userId
        }
        if let secretKey = args?["secretKey"] as? String {
            mv.secretKey = secretKey
        }
        if let offsetBottom = args?["offsetBottom"] as? Int {
            mv.offsetBottom = offsetBottom
        }
        if let beacon = args?["beacon"] as? [String: Any],
           let uuid = beacon["uuid"] as? String {
            mv.beaconUuid = uuid
        }
        if let launchUrlString = args?["launchUrl"] as? String,
           let launchUrl = URL(string: launchUrlString) {
            mv.launchURL = launchUrl
        }

        // `coverImage` is not yet plumbed through — the Dart side
        // currently sends an opaque ImageProvider that has no
        // stable wire representation. Tracked in `Flutter/DESIGN.md`
        // §8.

        self.mapView = mv
        self.methodChannel = FlutterMethodChannel(
            name: "\(PlatinumapsFlutterPlugin.viewType)/\(viewId)",
            binaryMessenger: messenger
        )
        super.init()
        mv.delegate = self
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
