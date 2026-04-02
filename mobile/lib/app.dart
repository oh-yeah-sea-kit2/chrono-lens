import 'package:flutter/material.dart';

import 'features/camera/camera_page.dart';

// TODO: Move to environment config or settings screen
const _defaultServerUrl = 'ws://192.168.1.100:8765/stream';

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
      home: const CameraPage(serverUrl: _defaultServerUrl),
    );
  }
}
