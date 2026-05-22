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
  Uri? _pendingLaunchUrl;

  /// `true` once the controller is wired to a live PlatformView.
  bool get isReady => _channel != null;

  /// Forwards a URL (typically captured from a Universal Link /
  /// Custom URL Scheme launch) to the web layer at runtime.
  ///
  /// If the controller is not yet attached to a `PlatinumapsMapView`,
  /// the URL is stashed and replayed when [attach] runs — so calling
  /// this in the same frame the host first inserts the widget is safe.
  /// The stash only keeps the most recent URL: a second call before
  /// attach overwrites the first.
  ///
  /// If the web layer has not yet emitted `web.ready` the native side
  /// performs a further stash and replays once it arrives, mirroring
  /// the iOS native SDK's `PMMapView.pushLaunchURL(_:)`.
  ///
  /// The native side restricts schemes to the SDK's allowlist
  /// (`http`, `https`, `tel`, `mailto`, `sms`, `geo`). Calling with
  /// any other scheme completes with a
  /// `PlatformException(code: 'invalid_arguments')`.
  Future<void> pushLaunchUrl(Uri url) async {
    final channel = _channel;
    if (channel == null) {
      _pendingLaunchUrl = url;
      return;
    }
    await channel.invokeMethod<void>('pushLaunchUrl', {'url': url.toString()});
  }

  /// Releases the controller. After this call [pushLaunchUrl] is a
  /// no-op. The host widget also detaches on its own `dispose`, so
  /// calling this is idempotent and optional.
  void dispose() {
    _channel = null;
    _pendingLaunchUrl = null;
  }

  // ---- Internal plumbing ----

  /// Called by `PlatinumapsMapView` when its PlatformView is created.
  /// Not part of the public API.
  void attach(MethodChannel channel) {
    assert(
      _channel == null,
      'PlatinumapsMapController is already attached. A single controller '
      'cannot drive two PlatinumapsMapView widgets at once.',
    );
    _channel = channel;
    final pending = _pendingLaunchUrl;
    if (pending != null) {
      _pendingLaunchUrl = null;
      // Fire-and-forget: the original `pushLaunchUrl` Future already
      // resolved when we stashed the URL, so there is nothing to
      // await on here.
      channel.invokeMethod<void>('pushLaunchUrl', {'url': pending.toString()});
    }
  }

  /// Called by `PlatinumapsMapView` on dispose or when the controller
  /// is swapped. Not part of the public API.
  void detach() {
    _channel = null;
  }
}
