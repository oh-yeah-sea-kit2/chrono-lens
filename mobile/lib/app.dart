import 'package:flutter/material.dart';

import 'features/camera/camera_page.dart';
import 'features/setup/setup_page.dart';
import 'services/server_config.dart';

class ChronoLensApp extends StatelessWidget {
  const ChronoLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chrono Lens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.amber.shade600,
          secondary: Colors.amber.shade300,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const _RootPage(),
    );
  }
}

/// Checks saved config and routes to SetupPage or CameraPage.
class _RootPage extends StatefulWidget {
  const _RootPage();

  @override
  State<_RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<_RootPage> {
  ServerConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ServerConfig.load();
    if (mounted) {
      setState(() {
        _config = config;
        _loading = false;
      });
    }
  }

  void _onConfigured() => _load();

  void _onResetConfig() async {
    await ServerConfig.clear();
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_config == null) {
      return SetupPage(onConfigured: _onConfigured);
    }

    return CameraPage(
      serverUrl: _config!.wsUrl,
      httpUrl: _config!.httpUrl,
      onResetServer: _onResetConfig,
    );
  }
}
