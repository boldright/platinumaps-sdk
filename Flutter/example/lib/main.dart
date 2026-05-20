import 'package:flutter/material.dart';
import 'package:platinumaps_flutter_sdk/platinumaps_flutter_sdk.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

void main() {
  runApp(const _ExampleApp());
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platinumaps Flutter example',
      theme: ThemeData(useMaterial3: true),
      home: const _ExampleHome(),
    );
  }
}

class _ExampleHome extends StatefulWidget {
  const _ExampleHome();

  @override
  State<_ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<_ExampleHome> {
  String? _lastOpenedLink;

  Future<void> _handleOpenLink(Uri url, {required bool sharedCookie}) async {
    setState(() => _lastOpenedLink = url.toString());
    await launcher.launchUrl(
      url,
      mode: launcher.LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platinumaps demo')),
      body: Stack(
        children: [
          PlatinumapsMapView(
            mapSlug: 'demo',
            locale: PlatinumapsLocale.ja,
            onOpenLink: _handleOpenLink,
          ),
          if (_lastOpenedLink != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: IgnorePointer(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Last opened: $_lastOpenedLink',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
