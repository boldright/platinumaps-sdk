import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platinumaps_beacon_options.dart';
import 'platinumaps_locale.dart';

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
typedef PlatinumapsOpenLinkCallback = void Function(
  Uri url, {
  required bool sharedCookie,
});

/// Embeds the Platinumaps web map as a Flutter widget.
///
/// The widget hosts the platform-native WebView (iOS `PMMapView`,
/// Android `PmWebView`) via a `PlatformView`. Configuration is passed
/// through to the native side at construction time; changing
/// configuration after the widget is built has no effect until the
/// widget is rebuilt with a new key.
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
    this.offsetBottom = 0,
    this.coverImage,
    this.beacon,
    this.launchUrl,
    this.onOpenLink,
  });

  /// The map identifier appended to `https://platinumaps.jp/maps/`.
  ///
  /// May include a sub-path (e.g. `demo/sr999`). Serialized as
  /// `mapSlug` on iOS and `mapPath` on Android — the two native SDKs
  /// disagree on the field name; the Flutter plugin glue translates.
  final String mapSlug;

  /// Optional extra query parameters merged into the map URL.
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

  /// When non-zero, the SDK reports a zeroed bottom safe-area inset
  /// to the web layer — useful when the host already adds its own
  /// bottom inset (e.g. a tab bar).
  final int offsetBottom;

  /// Splash image shown on top of the WebView until the web layer
  /// signals `web.ready`.
  ///
  /// **Not yet wired in v0.1.** The parameter is part of the public
  /// API for forward compatibility, but Dart `ImageProvider` has no
  /// stable wire representation across the platform channel and v0.1
  /// drops the value on both platforms. Until the parity follow-up
  /// in `DESIGN.md` §8 #5 lands, host a Flutter splash widget above
  /// the map in a `Stack` if you need one.
  final ImageProvider? coverImage;

  /// Beacon ranging configuration. Pass `null` to disable beacon
  /// scanning entirely.
  final PlatinumapsBeaconOptions? beacon;

  /// Initial deep-link URL captured from a Universal Link / Custom
  /// URL Scheme launch. The web layer consumes it once it is ready.
  ///
  /// Runtime pushes (the equivalent of the iOS native SDK's
  /// `pushLaunchURL`) are not supported in v0.1; rebuild the widget
  /// with a new [launchUrl] to retrigger.
  final Uri? launchUrl;

  /// Invoked when the embedded web map asks the host to open a URL
  /// outside the WebView.
  ///
  /// When `null`, behaviour depends on the platform:
  ///
  /// * iOS — the native SDK's defaults apply:
  ///   `SFSafariViewController` for HTTPS/HTTP and `UIApplication.open`
  ///   for the other allowlisted schemes (`tel`, `mailto`, `sms`,
  ///   `geo`).
  /// * Android — `browse.inapp` (non-shared-cookie) links open via
  ///   Chrome Custom Tabs. `browse.app`, `map.navigate`, and
  ///   shared-cookie `browse.inapp` links are silently dropped: the
  ///   native Android SDK delegates those to the listener and has no
  ///   internal fallback. Supply a callback if your maps emit any of
  ///   those commands.
  final PlatinumapsOpenLinkCallback? onOpenLink;

  @override
  State<PlatinumapsMapView> createState() => _PlatinumapsMapViewState();
}

class _PlatinumapsMapViewState extends State<PlatinumapsMapView> {
  static const String _viewType = 'jp.co.boldright.platinumaps/map';

  MethodChannel? _channel;

  @override
  void dispose() {
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
      'offsetBottom': widget.offsetBottom,
      if (widget.beacon != null) 'beacon': widget.beacon!.toMap(),
      if (widget.launchUrl != null) 'launchUrl': widget.launchUrl!.toString(),
      // The native plugins consult this flag at creation time to decide
      // whether to attach themselves as the SDK's openLink listener.
      // Attaching unconditionally would suppress the native SDK's
      // default link-handling fallbacks (SFSafariViewController on iOS,
      // Custom Tabs on Android) whenever the host omits onOpenLink.
      'hasOpenLinkHandler': widget.onOpenLink != null,
    };
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    channel.setMethodCallHandler(_handleMethodCall);
    _channel = channel;
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onOpenLink':
        final callback = widget.onOpenLink;
        if (callback == null) return null;
        // The platform channel can deliver `null`, a `Map<dynamic,
        // dynamic>`, or unexpected types from a misbehaving native
        // side. Tolerate all of them by bailing out cleanly instead
        // of throwing into the platform channel runtime.
        final rawArgs = call.arguments;
        if (rawArgs is! Map) return null;
        final args = Map<String, Object?>.from(rawArgs);
        final urlString = args['url'];
        if (urlString is! String) return null;
        final uri = Uri.tryParse(urlString);
        if (uri == null) return null;
        final sharedCookie = args['sharedCookie'] == true;
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
