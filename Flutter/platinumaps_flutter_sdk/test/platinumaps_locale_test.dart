import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  group('PlatinumapsLocale.code', () {
    test('emits the wire values the web app and the native SDKs share', () {
      // These exact strings are also baked into the iOS `PMLocale`
      // raw values and the Android `culture` query parameter — keep
      // the three in sync. The values intentionally cross BCP-47
      // boundaries (e.g. `zh-cn` rather than `zh-Hans`) because they
      // mirror what the web app already accepts.
      expect(PlatinumapsLocale.ja.code, 'ja');
      expect(PlatinumapsLocale.en.code, 'en');
      expect(PlatinumapsLocale.zhHans.code, 'zh-cn');
      expect(PlatinumapsLocale.zhHant.code, 'zh-tw');
      expect(PlatinumapsLocale.ko.code, 'ko');
      expect(PlatinumapsLocale.fr.code, 'fr');
      expect(PlatinumapsLocale.es.code, 'es');
      expect(PlatinumapsLocale.vi.code, 'vi');
      expect(PlatinumapsLocale.id.code, 'id');
      expect(PlatinumapsLocale.my.code, 'my');
      expect(PlatinumapsLocale.th.code, 'th');
    });

    test('every enum value has a non-empty code', () {
      for (final locale in PlatinumapsLocale.values) {
        expect(locale.code, isNotEmpty,
            reason: 'locale $locale must declare a non-empty wire code');
      }
    });

    test('codes are unique across all enum values', () {
      final codes = PlatinumapsLocale.values.map((l) => l.code).toList();
      expect(codes.toSet().length, codes.length,
          reason: 'PlatinumapsLocale codes must not collide');
    });
  });
}
