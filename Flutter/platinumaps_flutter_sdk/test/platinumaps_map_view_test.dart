import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  group('PlatinumapsMapView constructor', () {
    test('preserves only mapSlug when nothing else is supplied', () {
      const widget = PlatinumapsMapView(mapSlug: 'demo');
      expect(widget.mapSlug, 'demo');
      expect(widget.queryParams, isNull);
      expect(widget.locale, isNull);
      expect(widget.appStoreId, isNull);
      expect(widget.userId, isNull);
      expect(widget.secretKey, isNull);
      expect(widget.coverImage, isNull);
      expect(widget.beacon, isNull);
      expect(widget.launchUrl, isNull);
      expect(widget.onOpenLink, isNull);
    });

    test('offsetBottom defaults to 0', () {
      const widget = PlatinumapsMapView(mapSlug: 'demo');
      expect(widget.offsetBottom, 0);
    });

    test('propagates every constructor argument', () {
      const beacon = PlatinumapsBeaconOptions(
        uuid: '01234567-89AB-CDEF-0123-456789ABCDEF',
        minSample: 4,
        maxHistory: 32,
        memo: 'demo-zone',
      );
      final launchUrl = Uri.parse('https://platinumaps.jp/maps/demo/sr999');
      void onOpenLink(Uri url, {required bool sharedCookie}) {}

      final widget = PlatinumapsMapView(
        mapSlug: 'demo/sr999',
        queryParams: const {'key1': 'value1'},
        locale: PlatinumapsLocale.ja,
        appStoreId: '1234567890',
        userId: 'u-1',
        secretKey: 's-1',
        offsetBottom: 24,
        beacon: beacon,
        launchUrl: launchUrl,
        onOpenLink: onOpenLink,
      );

      expect(widget.mapSlug, 'demo/sr999');
      expect(widget.queryParams, {'key1': 'value1'});
      expect(widget.locale, PlatinumapsLocale.ja);
      expect(widget.appStoreId, '1234567890');
      expect(widget.userId, 'u-1');
      expect(widget.secretKey, 's-1');
      expect(widget.offsetBottom, 24);
      expect(widget.beacon, same(beacon));
      expect(widget.launchUrl, launchUrl);
      expect(widget.onOpenLink, same(onOpenLink));
    });
  });

  group('PlatinumapsOpenLinkCallback', () {
    test(
      'callback signature accepts http and platinumaps-shared-cookie urls',
      () {
        // Smoke-checks the typedef shape. Schemes outside the native
        // allowlist (http, https, tel, mailto, sms, geo) are dropped by
        // the native SDK before the callback fires; this test only
        // verifies the callback is invokable for whitelisted schemes.
        Uri? lastUrl;
        bool? lastShared;
        void callback(Uri url, {required bool sharedCookie}) {
          lastUrl = url;
          lastShared = sharedCookie;
        }

        callback(Uri.parse('https://example.com'), sharedCookie: false);
        expect(lastUrl, Uri.parse('https://example.com'));
        expect(lastShared, isFalse);

        callback(
          Uri.parse('https://platinumaps.jp/maps/demo/reward'),
          sharedCookie: true,
        );
        expect(lastShared, isTrue);
      },
    );
  });
}
