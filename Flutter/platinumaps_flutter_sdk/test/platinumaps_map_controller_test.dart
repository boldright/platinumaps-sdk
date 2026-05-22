import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  group('PlatinumapsMapController', () {
    test('isReady is false until attached', () {
      final controller = PlatinumapsMapController();
      expect(controller.isReady, isFalse);
    });

    test(
      'pushLaunchUrl before attach stashes the URL without throwing',
      () async {
        final controller = PlatinumapsMapController();
        // Should resolve immediately, without throwing or dispatching.
        await controller.pushLaunchUrl(Uri.parse('https://example.com'));
        expect(controller.isReady, isFalse);
      },
    );

    test('stashed pre-attach launch URL is replayed on attach', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test/platinumaps_map_controller');
      final invocations = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invocations.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = PlatinumapsMapController();
      await controller.pushLaunchUrl(
        Uri.parse('https://platinumaps.jp/maps/demo/stashed'),
      );
      expect(invocations, isEmpty);

      controller.attach(channel);
      // The replay is fire-and-forget. Pump the microtask queue so
      // the mock handler observes it before the assertions run.
      await Future<void>.delayed(Duration.zero);

      expect(invocations, hasLength(1));
      final args = invocations.single.arguments as Map;
      expect(args['url'], 'https://platinumaps.jp/maps/demo/stashed');
    });

    test('a second pre-attach push overwrites the first', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test/platinumaps_map_controller');
      final invocations = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invocations.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = PlatinumapsMapController();
      await controller.pushLaunchUrl(Uri.parse('https://example.com/first'));
      await controller.pushLaunchUrl(Uri.parse('https://example.com/second'));

      controller.attach(channel);
      await Future<void>.delayed(Duration.zero);

      expect(invocations, hasLength(1));
      final args = invocations.single.arguments as Map;
      expect(args['url'], 'https://example.com/second');
    });

    test('dispose discards any pending pre-attach launch URL', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test/platinumaps_map_controller');
      final invocations = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invocations.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final controller = PlatinumapsMapController();
      await controller.pushLaunchUrl(Uri.parse('https://example.com/dropped'));
      controller.dispose();

      controller.attach(channel);
      await Future<void>.delayed(Duration.zero);

      expect(invocations, isEmpty);
    });

    test('pushLaunchUrl invokes the platform channel after attach', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test/platinumaps_map_controller');
      final invocations = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invocations.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
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
    });

    test('detach reverts isReady to false', () {
      final controller = PlatinumapsMapController();
      controller.attach(const MethodChannel('test/platinumaps_map_controller'));
      controller.detach();
      expect(controller.isReady, isFalse);
    });

    test('dispose reverts isReady to false', () {
      final controller = PlatinumapsMapController();
      controller.attach(const MethodChannel('test/platinumaps_map_controller'));
      controller.dispose();
      expect(controller.isReady, isFalse);
    });

    test('attaching twice without detach fires an assert in debug mode', () {
      final controller = PlatinumapsMapController();
      controller.attach(const MethodChannel('test/platinumaps_map_controller'));
      expect(
        () => controller.attach(
          const MethodChannel('test/platinumaps_map_controller_2'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
