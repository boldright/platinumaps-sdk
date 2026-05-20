import Flutter
import UIKit

/// Creates a `PlatinumapsPlatformView` for each `PlatinumapsMapView`
/// widget the Dart side builds.
final class PlatinumapsPlatformViewFactory: NSObject, FlutterPlatformViewFactory {

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        // PlatformView factories are invoked on the main thread by
        // Flutter; assume the main-actor isolation so we can construct
        // the MainActor-isolated `PlatinumapsPlatformView` (which in
        // turn touches the `@MainActor` PMMapView) without hopping.
        return MainActor.assumeIsolated {
            PlatinumapsPlatformView(
                frame: frame,
                viewIdentifier: viewId,
                arguments: args as? [String: Any],
                messenger: messenger
            )
        }
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
