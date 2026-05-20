import Flutter
import UIKit
#if SWIFT_PACKAGE
import PlatinumapsSDK
#endif

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
        return PlatinumapsPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args as? [String: Any],
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
