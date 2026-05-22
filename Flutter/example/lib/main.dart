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
      // Material 3 is the default since Flutter 3.16, so we don't pass
      // `useMaterial3: true` explicitly.
      theme: ThemeData(),
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
  final _controller = PlatinumapsMapController();
  String? _lastOpenedLink;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleOpenLink(Uri url, {required bool sharedCookie}) async {
    setState(() => _lastOpenedLink = url.toString());
    try {
      await launcher.launchUrl(
        url,
        mode: launcher.LaunchMode.externalApplication,
      );
    } catch (error, stack) {
      // The SDK callback is fire-and-forget, so any exception thrown
      // by `launcher.launchUrl` would otherwise become an unobserved
      // Future error and crash the app at the next Dart microtask
      // pump. Log it and move on.
      debugPrint('Failed to launch $url: $error\n$stack');
    }
  }

  // Stands in for the Universal Link / Custom URL Scheme entry the
  // host would normally receive at runtime. Tap the FAB to verify the
  // controller actually forwards the URL through to the WebView
  // without rebuilding the PlatformView.
  Future<void> _pushDemoLaunchUrl() async {
    await _controller.pushLaunchUrl(
      Uri.parse('https://platinumaps.jp/maps/demo'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platinumaps demo')),
      floatingActionButton: FloatingActionButton(
        onPressed: _pushDemoLaunchUrl,
        tooltip: 'Push a demo deep link via PlatinumapsMapController',
        child: const Icon(Icons.link),
      ),
      body: Stack(
        children: [
          PlatinumapsMapView(
            mapSlug: 'demo',
            controller: _controller,
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
