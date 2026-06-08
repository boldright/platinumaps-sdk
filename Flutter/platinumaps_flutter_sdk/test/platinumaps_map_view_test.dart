import 'package:flutter/widgets.dart';
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
      expect(widget.beacon, isNull);
      expect(widget.launchUrl, isNull);
      expect(widget.onOpenLink, isNull);
      expect(widget.controller, isNull);
    });

    test('safeAreaTop and safeAreaBottom default to null', () {
      const widget = PlatinumapsMapView(mapSlug: 'demo');
      expect(widget.safeAreaTop, isNull);
      expect(widget.safeAreaBottom, isNull);
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
      final controller = PlatinumapsMapController();

      final widget = PlatinumapsMapView(
        mapSlug: 'demo/sr999',
        queryParams: const {'key1': 'value1'},
        locale: PlatinumapsLocale.ja,
        appStoreId: '1234567890',
        userId: 'u-1',
        secretKey: 's-1',
        safeAreaTop: 48,
        safeAreaBottom: 16,
        beacon: beacon,
        launchUrl: launchUrl,
        onOpenLink: onOpenLink,
        controller: controller,
      );

      expect(widget.mapSlug, 'demo/sr999');
      expect(widget.queryParams, {'key1': 'value1'});
      expect(widget.locale, PlatinumapsLocale.ja);
      expect(widget.appStoreId, '1234567890');
      expect(widget.userId, 'u-1');
      expect(widget.secretKey, 's-1');
      expect(widget.safeAreaTop, 48);
      expect(widget.safeAreaBottom, 16);
      expect(widget.beacon, same(beacon));
      expect(widget.launchUrl, launchUrl);
      expect(widget.onOpenLink, same(onOpenLink));
      expect(widget.controller, same(controller));
    });
  });

  group('PlatinumapsMapView safe-area resolution', () {
    Map<dynamic, dynamic> creationParamsOf(WidgetTester tester) {
      final view = tester.widget<AndroidView>(find.byType(AndroidView));
      return view.creationParams! as Map<dynamic, dynamic>;
    }

    Widget host(PlatinumapsMapView child) => MediaQuery(
      data: const MediaQueryData(
        padding: EdgeInsets.only(top: 44, bottom: 34),
      ),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

    testWidgets('null insets resolve to the ambient MediaQuery padding', (
      tester,
    ) async {
      await tester.pumpWidget(host(const PlatinumapsMapView(mapSlug: 'demo')));
      final params = creationParamsOf(tester);
      expect(params['safeAreaTop'], 44);
      expect(params['safeAreaBottom'], 34);
    });

    testWidgets('explicit insets override the ambient MediaQuery padding', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const PlatinumapsMapView(
            mapSlug: 'demo',
            safeAreaTop: 0,
            safeAreaBottom: 8,
          ),
        ),
      );
      final params = creationParamsOf(tester);
      expect(params['safeAreaTop'], 0);
      expect(params['safeAreaBottom'], 8);
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
