import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  group('PlatinumapsMapController', () {
    test('isReady is false until attached', () {
      final controller = PlatinumapsMapController();
      expect(controller.isReady, isFalse);
    });

    test('pushLaunchUrl is a no-op before attach', () async {
      final controller = PlatinumapsMapController();
      // Should not throw; just resolves without dispatching anything.
      await controller.pushLaunchUrl(Uri.parse('https://example.com'));
      expect(controller.isReady, isFalse);
    });

    test(
      'pushLaunchUrl invokes the platform channel after attach',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const channel = MethodChannel('test/platinumaps_map_controller');
        final invocations = <MethodCall>[];
        TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              invocations.add(call);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final controller = PlatinumapsMapController();
        controller.attach(channel);
        expect(controller.isReady, isTrue);

        await controller.pushLaunchUrl(
          Uri.parse('https://platinumaps.jp/maps/demo'),
        );

        expect(invocations, hasLength(1));
        expect(invocations.single.method, 'pushLaunchUrl');
        final args = invocations.single.arguments as Map;
        expect(args['url'], 'https://platinumaps.jp/maps/demo');
      },
    );

    test('detach reverts isReady to false', () {
      final controller = PlatinumapsMapController();
      controller.attach(const MethodChannel('test/platinumaps_map_controller'));
      controller.detach();
      expect(controller.isReady, isFalse);
    });
  });
}
