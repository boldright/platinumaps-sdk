import 'dart:async';

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

  /// Mirrors the native plugins' allowlist so input that would later
  /// be rejected can fail synchronously rather than across the
  /// channel boundary.
  static const Set<String> _allowedSchemes = {
    'http',
    'https',
    'tel',
    'mailto',
    'sms',
    'geo',
  };

  MethodChannel? _channel;
  _PendingPush? _pending;

  /// `true` once the controller is wired to a live PlatformView.
  bool get isReady => _channel != null;

  /// Forwards a URL (typically captured from a Universal Link /
  /// Custom URL Scheme launch) to the web layer at runtime.
  ///
  /// The returned [Future] completes when the native side has accepted
  /// the URL. If the controller is not yet attached to a
  /// [PlatinumapsMapView] the URL is stashed and replayed when
  /// [attach] runs; the same [Future] completes (or errors) with the
  /// replay's result. A second call before attach supersedes the
  /// first — the first [Future] then completes with a [StateError].
  ///
  /// Likewise, if the controller is detached or disposed while a URL
  /// is still pending, the [Future] completes with a [StateError]
  /// rather than hanging.
  ///
  /// If the web layer has not yet emitted `web.ready` the native side
  /// performs a further stash and replays once it arrives, mirroring
  /// the iOS native SDK's `PMMapView.pushLaunchURL(_:)`.
  ///
  /// Schemes are restricted to the SDK's allowlist
  /// (`http`, `https`, `tel`, `mailto`, `sms`, `geo`). Calling with
  /// any other scheme throws an [ArgumentError] synchronously.
  Future<void> pushLaunchUrl(Uri url) {
    final scheme = url.scheme.toLowerCase();
    if (!_allowedSchemes.contains(scheme)) {
      throw ArgumentError.value(
        url,
        'url',
        'pushLaunchUrl requires a URL with an allowlisted scheme '
            '(${_allowedSchemes.join(', ')})',
      );
    }
    final channel = _channel;
    if (channel != null) {
      return channel.invokeMethod<void>('pushLaunchUrl', {
        'url': url.toString(),
      });
    }
    _abortPending(
      StateError(
        'pushLaunchUrl was superseded by a later call before the '
        'controller attached to a PlatinumapsMapView.',
      ),
    );
    final completer = Completer<void>();
    _pending = _PendingPush(url, completer);
    return completer.future;
  }

  /// Releases the controller. Any pending [pushLaunchUrl] [Future]
  /// completes with a [StateError]. The host widget also detaches on
  /// its own `dispose`, so calling this is idempotent and optional.
  void dispose() {
    _channel = null;
    _abortPending(
      StateError('PlatinumapsMapController was disposed before attach.'),
    );
  }

  // ---- Internal plumbing ----

  /// Called by `PlatinumapsMapView` when its PlatformView is created.
  /// Not part of the public API.
  void attach(MethodChannel channel) {
    if (_channel != null) {
      throw StateError(
        'PlatinumapsMapController is already attached. A single controller '
        'cannot drive two PlatinumapsMapView widgets at once.',
      );
    }
    _channel = channel;
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      channel
          .invokeMethod<void>('pushLaunchUrl', {'url': pending.url.toString()})
          .then(
            (_) => pending.completer.complete(),
            onError: (Object error, StackTrace stackTrace) {
              pending.completer.completeError(error, stackTrace);
            },
          );
    }
  }

  /// Called by `PlatinumapsMapView` on dispose or when the controller
  /// is swapped. Any pending [pushLaunchUrl] [Future] completes with a
  /// [StateError]. Not part of the public API.
  void detach() {
    _channel = null;
    _abortPending(
      StateError(
        'PlatinumapsMapController detached before the pending URL was sent.',
      ),
    );
  }

  void _abortPending(Object error) {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    pending.completer.completeError(error);
  }
}

class _PendingPush {
  _PendingPush(this.url, this.completer);

  final Uri url;
  final Completer<void> completer;
}
