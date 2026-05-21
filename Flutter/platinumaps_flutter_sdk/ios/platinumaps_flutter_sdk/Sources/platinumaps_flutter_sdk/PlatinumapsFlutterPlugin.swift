import Flutter
import UIKit

/// Entry point of the Platinumaps Flutter plugin on iOS.
///
/// Registers a single PlatformView factory keyed by
/// `jp.co.boldright.platinumaps/map`. Each `PlatinumapsMapView` widget
/// on the Dart side ends up backed by a `PMMapView` (the native iOS
/// SDK's public UIView) hosted via `UiKitView`.
///
/// No application-lifecycle wiring is required from the host Flutter
/// app — `PMMapView` self-installs the same `UIApplication`
/// foreground/background observers that the native iOS SDK has
/// always installed.
public class PlatinumapsFlutterPlugin: NSObject, FlutterPlugin {

    public static let viewType: String = "jp.co.boldright.platinumaps/map"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = PlatinumapsPlatformViewFactory(
            messenger: registrar.messenger()
        )
        registrar.register(factory, withId: viewType)
    }
}
