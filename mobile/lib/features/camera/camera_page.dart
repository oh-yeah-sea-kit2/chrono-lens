import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/era.dart';
import '../../models/frame_message.dart';
import '../../services/frame_processor.dart';
import '../../services/websocket_service.dart';
import 'widgets/crossfade_renderer.dart';
import 'widgets/era_selector.dart';
import 'widgets/latency_overlay.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.serverUrl, this.onResetServer});

  final String serverUrl;
  final VoidCallback? onResetServer;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late WebSocketService _ws;
  late FrameProcessor _processor;
  StreamSubscription<ResultMessage>? _resultSub;

  Uint8List? _latestJpeg;
  double _rttMs = 0;
  double _procMs = 0;
  bool _showDebug = false;
  Era _selectedEra = Era.taisho;

  // Track the latest frameId to discard stale results
  int _latestFrameId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ws = WebSocketService(serverUrl: widget.serverUrl);
    _processor = FrameProcessor();
    _init();
  }

  Future<void> _init() async {
    await _requestPermissions();
    await _initCamera();
    await _ws.connect();
    _listenResults();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera].request();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    if (!mounted) return;

    await controller.startImageStream(_onCameraFrame);
    setState(() => _cameraController = controller);
  }

  void _listenResults() {
    _resultSub = _ws.resultStream.listen((result) {
      debugPrint(
        '[Camera] Result frame_id=${result.frameId} '
        'rtt=${result.rttMs.toStringAsFixed(0)}ms '
        'proc=${result.procMs.toStringAsFixed(0)}ms '
        'jpeg=${result.jpeg.length}B '
        'dropped=${result.isDropped}',
      );

      // Discard stale results (more than 3 frames behind)
      if (result.frameId < _latestFrameId - 3) {
        debugPrint('[Camera] Discarding stale frame_id=${result.frameId} (latest=$_latestFrameId)');
        return;
      }
      _latestFrameId = result.frameId;

      _processor.onResultReceived(result.rttMs);

      if (mounted) {
        setState(() {
          _latestJpeg = result.jpeg;
          _rttMs = result.rttMs;
          _procMs = result.procMs;
        });
      }
    });
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    _processor.era = _selectedEra;
    final bytes = await _processor.process(image);
    if (bytes != null) {
      debugPrint('[Camera] Sending frame ${_processor.stats}');
      _ws.sendFrame(bytes);
    }
  }

  void _onEraSelected(Era era) {
    setState(() => _selectedEra = era);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      ctrl.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      ctrl.startImageStream(_onCameraFrame);
      _ws.connect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultSub?.cancel();
    _cameraController?.dispose();
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main view: AI result or camera preview fallback
          if (_latestJpeg != null)
            CrossfadeRenderer(
              jpeg: _latestJpeg!,
              fadeDuration: const Duration(milliseconds: 500),
            )
          else if (_cameraController?.value.isInitialized == true)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator()),

          // Connection status banner
          _ConnectionBanner(state: _ws.state),

          // Debug overlay
          if (_showDebug)
            LatencyOverlay(
              rttMs: _rttMs,
              procMs: _procMs,
              stats: _processor.stats,
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomControls(
              selectedEra: _selectedEra,
              showDebug: _showDebug,
              onEraTap: () => EraSelector.show(
                context,
                current: _selectedEra,
                onSelected: _onEraSelected,
              ),
              onDebugToggle: () => setState(() => _showDebug = !_showDebug),
              onResetServer: widget.onResetServer,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.state});
  final WsState state;

  @override
  Widget build(BuildContext context) {
    if (state == WsState.connected) return const SizedBox.shrink();

    final (color, label) = switch (state) {
      WsState.connecting => (Colors.orange, '接続中...'),
      WsState.reconnecting => (Colors.red, '再接続中...'),
      WsState.disconnected => (Colors.red.shade900, '未接続'),
      WsState.connected => (Colors.transparent, ''),
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: color,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.selectedEra,
    required this.showDebug,
    required this.onEraTap,
    required this.onDebugToggle,
    this.onResetServer,
  });

  final Era selectedEra;
  final bool showDebug;
  final VoidCallback onEraTap;
  final VoidCallback onDebugToggle;
  final VoidCallback? onResetServer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Debug toggle
          IconButton(
            icon: Icon(
              showDebug ? Icons.bar_chart : Icons.bar_chart_outlined,
              color: Colors.white70,
            ),
            onPressed: onDebugToggle,
          ),

          // Era selector button
          GestureDetector(
            onTap: onEraTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedEra.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, color: Colors.white70, size: 18),
                ],
              ),
            ),
          ),

          // Server settings reset
          IconButton(
            icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
            onPressed: onResetServer,
            tooltip: 'サーバー設定',
          ),
        ],
      ),
    );
  }
}
