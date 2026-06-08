import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  group('PlatinumapsBeaconOptions.toMap', () {
    const sampleUuid = '01234567-89AB-CDEF-0123-456789ABCDEF';

    test('emits only `uuid` when no optional fields are set', () {
      const options = PlatinumapsBeaconOptions(uuid: sampleUuid);
      expect(options.toMap(), {'uuid': sampleUuid});
    });

    test('emits every field when all are set', () {
      const options = PlatinumapsBeaconOptions(
        uuid: sampleUuid,
        minSample: 4,
        maxHistory: 32,
        memo: 'demo-zone',
      );
      expect(options.toMap(), {
        'uuid': sampleUuid,
        'minSample': 4,
        'maxHistory': 32,
        'memo': 'demo-zone',
      });
    });

    test(
      'omits null optional fields rather than emitting an explicit null',
      () {
        const options = PlatinumapsBeaconOptions(
          uuid: sampleUuid,
          minSample: 3,
          // maxHistory and memo intentionally left null
        );
        final map = options.toMap();
        expect(map, containsPair('uuid', sampleUuid));
        expect(map, containsPair('minSample', 3));
        expect(map.containsKey('maxHistory'), isFalse);
        expect(map.containsKey('memo'), isFalse);
      },
    );
  });
}
