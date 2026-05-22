import 'package:flutter/services.dart';

/// Imperative handle to a [PlatinumapsMapView].
///
/// Pass an instance to the widget's `controller:` parameter and call
/// the methods below to drive the map at runtime — without rebuilding
/// the widget (which would tear the PlatformView down and lose the
/// WebView's scroll position, selected spot, session cookies, etc.).
class PlatinumapsMapController {
  /// Creates a detached controller. It becomes active once the widget
  /// it is attached to has built its PlatformView.
  PlatinumapsMapController();

  MethodChannel? _channel;

  /// `true` once the controller is wired to a live PlatformView.
  ///
  /// Methods called before the widget has built — for example, during
  /// the same frame the host first inserts `PlatinumapsMapView` into
  /// the tree — are silently dropped. Wait for the next frame, or
  /// gate calls on this flag.
  bool get isReady => _channel != null;

  /// Forwards a URL (typically captured from a Universal Link /
  /// Custom URL Scheme launch) to the web layer at runtime.
  ///
  /// If the web layer has not yet emitted `web.ready` the native side
  /// stashes the URL and replays it as soon as it arrives, mirroring
  /// the iOS native SDK's `PMMapView.pushLaunchURL(_:)`.
  ///
  /// The native side restricts schemes to the SDK's allowlist
  /// (`http`, `https`, `tel`, `mailto`, `sms`, `geo`). Calling with
  /// any other scheme completes with a
  /// `PlatformException(code: 'invalid_arguments')`.
  ///
  /// Calls made before the underlying PlatformView is attached (see
  /// [isReady]) are silently dropped — they neither throw nor
  /// stash the URL. Wait for the next frame, or gate on [isReady].
  Future<void> pushLaunchUrl(Uri url) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('pushLaunchUrl', {
      'url': url.toString(),
    });
  }

  // ---- Internal plumbing ----

  /// Called by `PlatinumapsMapView` when its PlatformView is created.
  /// Not part of the public API.
  void attach(MethodChannel channel) {
    _channel = channel;
  }

  /// Called by `PlatinumapsMapView` on dispose or when the controller
  /// is swapped. Not part of the public API.
  void detach() {
    _channel = null;
  }
}
