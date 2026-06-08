// Integration tests for the Platinumaps Flutter example app.
//
// These run against a real device or simulator (the only place a
// PlatformView actually instantiates) but are kept network-free on
// purpose — they verify the host-app composition, not what the web
// layer renders. Network-dependent checks (`web.ready` arrival,
// `onOpenLink` firing for real platinumaps.jp links) belong in the
// manual-smoke-test column of DESIGN §7 because they depend on the
// production web layer and on hardware sensors.
//
// Run with:
//
//     cd Flutter/example
//     flutter test integration_test
//
// or, against a specific device:
//
//     flutter test integration_test --device-id=<simulator-or-device-id>

import 'package:example/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots and mounts PlatinumapsMapView', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(
      find.byType(PlatinumapsMapView),
      findsOneWidget,
      reason: 'The example app must render a PlatinumapsMapView on launch.',
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Platinumaps demo'), findsOneWidget);
  });

  testWidgets('the "last opened" overlay is hidden until onOpenLink fires', (
    tester,
  ) async {
    // The example app stacks an `IgnorePointer` banner above the
    // PlatformView, but only after the host's `onOpenLink` callback
    // has been invoked at least once. On a fresh launch (no link
    // has been opened) the banner must not be visible.
    app.main();
    await tester.pumpAndSettle();

    expect(find.textContaining('Last opened:'), findsNothing);
  });
}
