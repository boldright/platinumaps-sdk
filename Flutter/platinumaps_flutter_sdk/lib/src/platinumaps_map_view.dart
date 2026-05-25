import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platinumaps_beacon_options.dart';
import 'platinumaps_locale.dart';
import 'platinumaps_map_controller.dart';

/// Signature for the callback invoked when the embedded web map asks
/// the host to open a link outside the WebView.
///
/// [sharedCookie] is `true` when the web layer marked the link as one
/// that must carry the current session (e.g., stamp-rally reward
/// downloads). In that case the host should open the URL in an in-app
/// browser that shares cookies with the embedded WebView. When
/// `false`, the link is safe to hand off to the system browser.
///
/// Schemes are restricted by the native SDK to a conservative
/// allowlist (`http`, `https`, `tel`, `mailto`, `sms`, `geo`) before
/// the callback fires.
typedef PlatinumapsOpenLinkCallback =
    void Function(Uri url, {required bool sharedCookie});

/// Embeds the Platinumaps web map as a Flutter widget.
///
/// The widget hosts the platform-native WebView via a `PlatformView`.
/// Configuration values are consumed at construction; later rebuilds
/// do not propagate (rebuild with a new key to change them). The one
/// exception is [onOpenLink], which is re-read on every callback. For
/// runtime operations that must not lose the WebView state (scroll
/// position, session cookies, …) attach a [PlatinumapsMapController]
/// through [controller] and call its methods.
class PlatinumapsMapView extends StatefulWidget {
  /// Creates a Platinumaps map widget.
  const PlatinumapsMapView({
    super.key,
    required this.mapSlug,
    this.queryParams,
    this.locale,
    this.appStoreId,
    this.userId,
    this.secretKey,
    this.safeAreaTop = 0,
    this.safeAreaBottom = 0,
    this.beacon,
    this.launchUrl,
    this.onOpenLink,
    this.controller,
  }) : assert(mapSlug != '', 'mapSlug must not be empty'),
       assert(safeAreaTop >= 0, 'safeAreaTop must not be negative'),
       assert(safeAreaBottom >= 0, 'safeAreaBottom must not be negative');

  /// The map identifier appended to `https://platinumaps.jp/maps/`.
  ///
  /// May include a sub-path (e.g. `demo/sr999`).
  final String mapSlug;

  /// Optional extra query parameters merged into the map URL.
  ///
  /// The keys are interpreted by the Platinumaps web layer — refer to
  /// the Platinumaps web app documentation for the supported
  /// parameter catalogue.
  final Map<String, String>? queryParams;

  /// Forces the map UI language. When `null`, the WebView's
  /// `Accept-Language` (derived from the host platform's locale
  /// settings) determines the language.
  final PlatinumapsLocale? locale;

  /// iOS-only. The numeric App Store ID (e.g. `"1234567890"`) used by
  /// the `app.review` command to open the App Store review page.
  /// Ignored on Android.
  final String? appStoreId;

  /// Opaque user identifier the web app may consume via `app.info`.
  final String? userId;

  /// Opaque shared secret the web app may consume via `app.info`.
  ///
  /// Treat this as sensitive: only set it when the host application
  /// has a legitimate need for the web layer to authenticate the
  /// user.
  final String? secretKey;

  /// Top safe-area inset reported to the web layer, in **logical
  /// pixels** (the same unit `MediaQuery.of(context).padding` uses).
  ///
  /// Pass `MediaQuery.of(context).padding.top` when the map fills the
  /// screen and you want the web UI to inset itself under the status
  /// bar / notch. Pass `0` when the host is already drawing chrome
  /// above the map (e.g. an `AppBar`) and the map's own coordinate
  /// space is already inset.
  final int safeAreaTop;

  /// Bottom safe-area inset reported to the web layer, in **logical
  /// pixels**. Same conventions as [safeAreaTop].
  final int safeAreaBottom;

  /// Beacon ranging configuration. Pass `null` to disable beacon
  /// scanning entirely.
  final PlatinumapsBeaconOptions? beacon;

  /// Initial deep-link URL captured from a Universal Link / Custom
  /// URL Scheme launch. The web layer consumes it once it is ready.
  ///
  /// For URLs that arrive *after* the widget has mounted (e.g. a
  /// later Universal Link in the same session) use
  /// [PlatinumapsMapController.pushLaunchUrl] instead; rebuilding the
  /// widget would tear the WebView down and lose its state.
  final Uri? launchUrl;

  /// Invoked when the embedded web map asks the host to open a URL
  /// outside the WebView. Re-read on every callback, so it is safe to
  /// swap in a non-null handler on a later rebuild.
  ///
  /// When `null`, the SDK falls back to its built-in handling:
  ///
  /// * iOS — `SFSafariViewController` for HTTPS/HTTP (a navigation
  ///   stack with shared cookies for shared-cookie links) and
  ///   `UIApplication.open` for the other allowlisted schemes
  ///   (`tel`, `mailto`, `sms`, `geo`).
  /// * Android — Chrome Custom Tabs for HTTPS/HTTP. Other allowlisted
  ///   schemes are silently dropped (the bundled native SDK has no
  ///   external-app launcher today).
  final PlatinumapsOpenLinkCallback? onOpenLink;

  /// Optional imperative handle. Attach one to drive the map at
  /// runtime (e.g. forwarding a Universal Link via
  /// [PlatinumapsMapController.pushLaunchUrl]) without rebuilding the
  /// widget.
  final PlatinumapsMapController? controller;

  @override
  State<PlatinumapsMapView> createState() => _PlatinumapsMapViewState();
}

class _PlatinumapsMapViewState extends State<PlatinumapsMapView> {
  static const String _viewType = 'jp.co.boldright.platinumaps/map';

  MethodChannel? _channel;

  @override
  void didUpdateWidget(PlatinumapsMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      final channel = _channel;
      if (channel != null) {
        widget.controller?.attach(channel);
      }
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Map<String, Object?> _creationParams() {
    return {
      'mapSlug': widget.mapSlug,
      if (widget.queryParams != null) 'queryParams': widget.queryParams,
      if (widget.locale != null) 'locale': widget.locale!.code,
      if (widget.appStoreId != null) 'appStoreId': widget.appStoreId,
      if (widget.userId != null) 'userId': widget.userId,
      if (widget.secretKey != null) 'secretKey': widget.secretKey,
      'safeAreaTop': widget.safeAreaTop,
      'safeAreaBottom': widget.safeAreaBottom,
      if (widget.beacon != null) 'beacon': widget.beacon!.toMap(),
      if (widget.launchUrl != null) 'launchUrl': widget.launchUrl!.toString(),
    };
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    channel.setMethodCallHandler(_handleMethodCall);
    _channel = channel;
    widget.controller?.attach(channel);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onOpenLink':
        // Returning 'fallback' tells the native side to run the SDK's
        // default link handler. Any other reply (null or a Map) means
        // the host claimed the link.
        final callback = widget.onOpenLink;
        if (callback == null) return 'fallback';
        // The platform channel can deliver `null`, a `Map<dynamic,
        // dynamic>`, or unexpected types from a misbehaving native
        // side. Tolerate all of them by bailing out cleanly instead
        // of throwing into the platform channel runtime.
        final rawArgs = call.arguments;
        if (rawArgs is! Map) return 'fallback';
        final urlString = rawArgs['url'];
        if (urlString is! String) return 'fallback';
        final uri = Uri.tryParse(urlString);
        if (uri == null) return 'fallback';
        final sharedCookie = rawArgs['sharedCookie'] == true;
        callback(uri, sharedCookie: sharedCookie);
        return null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = _creationParams();
    const codec = StandardMessageCodec();

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: _viewType,
          creationParams: params,
          creationParamsCodec: codec,
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: _viewType,
          creationParams: params,
          creationParamsCodec: codec,
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      default:
        return ErrorWidget.withDetails(
          message: 'PlatinumapsMapView is only supported on Android and iOS.',
        );
    }
  }
}
