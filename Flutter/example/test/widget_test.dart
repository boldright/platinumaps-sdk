import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';

void main() {
  testWidgets('renders the demo map scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlatinumapsMapView(mapSlug: 'demo'),
        ),
      ),
    );
    expect(find.byType(PlatinumapsMapView), findsOneWidget);
  });
}
