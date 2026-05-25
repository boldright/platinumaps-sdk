import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  group('PlatinumapsMapController', () {
    test('isReady is false until attached', () {
      final controller = PlatinumapsMapController();
      expect(controller.isReady, isFalse);
    });

    test('pushLaunchUrl before attach returns a pending Future', () async {
      final controller = PlatinumapsMapController();
      final future = controller.pushLaunchUrl(
        Uri.parse('https://example.com/stashed'),
      );
      var completed = false;
      future.then((_) => completed = true, onError: (_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(controller.isReady, isFalse);
      // Drain the pending Future so the test exits cleanly.
      controller.dispose();
      await expectLater(future, throwsStateError);
    });

    test(
      'stashed pre-attach launch URL Future resolves with the replay',
      () async {
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
        final pending = controller.pushLaunchUrl(
          Uri.parse('https://platinumaps.jp/maps/demo/stashed'),
        );
        expect(invocations, isEmpty);

        controller.attach(channel);
        await pending;

        expect(invocations, hasLength(1));
        final args = invocations.single.arguments as Map;
        expect(args['url'], 'https://platinumaps.jp/maps/demo/stashed');
      },
    );

    test(
      'replay error from the native side surfaces on the awaited Future',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const channel = MethodChannel('test/platinumaps_map_controller');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(code: 'invalid_arguments');
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final controller = PlatinumapsMapController();
        final pending = controller.pushLaunchUrl(
          Uri.parse('https://example.com/replayed'),
        );
        controller.attach(channel);

        await expectLater(pending, throwsA(isA<PlatformException>()));
      },
    );

    test(
      'a second pre-attach push supersedes the first with a StateError',
      () async {
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
        final first = controller.pushLaunchUrl(
          Uri.parse('https://example.com/first'),
        );
        final second = controller.pushLaunchUrl(
          Uri.parse('https://example.com/second'),
        );

        await expectLater(first, throwsStateError);

        controller.attach(channel);
        await second;

        expect(invocations, hasLength(1));
        final args = invocations.single.arguments as Map;
        expect(args['url'], 'https://example.com/second');
      },
    );

    test(
      'dispose completes any pending pre-attach Future with a StateError',
      () async {
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
        final pending = controller.pushLaunchUrl(
          Uri.parse('https://example.com/dropped'),
        );
        controller.dispose();

        await expectLater(pending, throwsStateError);

        controller.attach(channel);
        await Future<void>.delayed(Duration.zero);

        expect(invocations, isEmpty);
      },
    );

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

    test(
      'detach completes any pending pre-attach Future with a StateError',
      () async {
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
        final pending = controller.pushLaunchUrl(
          Uri.parse('https://example.com/dropped'),
        );
        controller.detach();

        await expectLater(pending, throwsStateError);

        controller.attach(channel);
        await Future<void>.delayed(Duration.zero);

        expect(invocations, isEmpty);
      },
    );

    test('dispose reverts isReady to false', () {
      final controller = PlatinumapsMapController();
      controller.attach(const MethodChannel('test/platinumaps_map_controller'));
      controller.dispose();
      expect(controller.isReady, isFalse);
    });

    test('pushLaunchUrl rejects URLs with a disallowed scheme', () async {
      final controller = PlatinumapsMapController();
      expect(
        () => controller.pushLaunchUrl(Uri.parse('javascript:alert(1)')),
        throwsArgumentError,
      );
      // The rejected URL must not have been stashed for replay.
      expect(controller.isReady, isFalse);
    });

    test('attaching twice without detach throws in both debug and release', () {
      final controller = PlatinumapsMapController();
      controller.attach(const MethodChannel('test/platinumaps_map_controller'));
      expect(
        () => controller.attach(
          const MethodChannel('test/platinumaps_map_controller_2'),
        ),
        throwsStateError,
      );
    });
  });
}
