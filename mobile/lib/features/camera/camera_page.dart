import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../models/era.dart';
import '../../services/capture_service.dart';
import '../../services/style_transfer_service.dart';
import '../result/result_page.dart';
import 'widgets/era_selector.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.serverUrl, this.onResetServer});

  final String serverUrl;
  final VoidCallback? onResetServer;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final _styleService = StyleTransferService();
  late CaptureService _captureService;

  Era _selectedEra = Era.taisho;
  Uint8List? _styledFrame; // Latest style-transferred preview frame
  bool _isCapturing = false; // Shutter in progress
  bool _modelReady = false;
  bool _processing = false; // Style transfer in progress for current frame

  // Stats
  int _frameCount = 0;
  int _styledCount = 0;
  double _lastStyleMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Extract base HTTP URL from WebSocket URL
    final httpUrl = widget.serverUrl
        .replaceFirst('ws://', 'http://')
        .replaceFirst('/stream', '');
    _captureService = CaptureService(baseUrl: httpUrl);
    _init();
  }

  Future<void> _init() async {
    await [Permission.camera].request();
    await _initCamera();
    await _loadStyleModel();
    await _setEraStyle(_selectedEra);
  }

  Future<void> _loadStyleModel() async {
    final loaded = await _styleService.loadModel();
    if (mounted) {
      setState(() => _modelReady = loaded);
    }
    if (!loaded) {
      debugPrint('[CameraPage] CoreML model not available, running without style transfer');
    }
  }

  Future<void> _setEraStyle(Era era) async {
    if (era.styleAsset == null) {
      _styleService.clearStyle();
      return;
    }
    try {
      final data = await rootBundle.load(era.styleAsset!);
      await _styleService.setStyle(data.buffer.asUint8List());
    } catch (e) {
      debugPrint('[CameraPage] Failed to load style asset: $e');
    }
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

  Future<void> _onCameraFrame(CameraImage image) async {
    _frameCount++;

    // Skip if already processing a frame or capturing
    if (_processing || _isCapturing) return;

    // Only process every 3rd frame (~10fps input to style transfer)
    if (_frameCount % 3 != 0) return;

    if (!_modelReady || !_styleService.isReady) return;

    _processing = true;
    final sw = Stopwatch()..start();

    try {
      // Convert camera frame to JPEG on main thread (fast path)
      final jpeg = await _cameraFrameToJpeg(image);
      if (jpeg == null) {
        _processing = false;
        return;
      }

      // Run style transfer via CoreML
      final styled = await _styleService.transferFrame(jpeg);
      sw.stop();

      if (styled != null && mounted) {
        setState(() {
          _styledFrame = styled;
          _styledCount++;
          _lastStyleMs = sw.elapsedMilliseconds.toDouble();
        });
      }
    } catch (e) {
      debugPrint('[CameraPage] Style transfer error: $e');
    } finally {
      _processing = false;
    }
  }

  Future<Uint8List?> _cameraFrameToJpeg(CameraImage image) async {
    try {
      // Copy bytes from native memory
      final planes = image.planes.map((p) => Uint8List.fromList(p.bytes)).toList();
      final strides = image.planes.map((p) => p.bytesPerRow).toList();

      return await compute(_encodeJpeg, _CameraData(
        width: image.width,
        height: image.height,
        planes: planes,
        strides: strides,
        planeCount: image.planes.length,
      ));
    } catch (e) {
      debugPrint('[CameraPage] JPEG encode error: $e');
      return null;
    }
  }

  /// Shutter: capture current frame and send to server for HQ transformation
  Future<void> _onShutter() async {
    if (_isCapturing) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      // Stop streaming to freeze preview
      await controller.stopImageStream();

      // Take a photo
      final xFile = await controller.takePicture();
      final originalJpeg = await xFile.readAsBytes();

      if (!mounted) return;

      // Navigate to result page (it handles the server call)
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultPage(
          originalJpeg: Uint8List.fromList(originalJpeg),
          era: _selectedEra,
          captureService: _captureService,
          // Also pass the styled preview as a quick preview while loading
          styledPreview: _styledFrame,
        ),
      ));

      // Resume camera after returning
      if (mounted && controller.value.isInitialized) {
        await controller.startImageStream(_onCameraFrame);
      }
    } catch (e) {
      debugPrint('[CameraPage] Shutter error: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _onEraSelected(Era era) {
    setState(() => _selectedEra = era);
    _setEraStyle(era);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      ctrl.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      ctrl.startImageStream(_onCameraFrame);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main view: styled frame or camera fallback
          if (_styledFrame != null)
            Image.memory(
              _styledFrame!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else if (_cameraController?.value.isInitialized == true)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator()),

          // Status indicator
          if (!_modelReady)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'モデル読み込み中...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),

          // Debug overlay
          if (_styledCount > 0)
            Positioned(
              top: 60,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Style ${_lastStyleMs.toStringAsFixed(0)}ms  #$_styledCount',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),

          // Capture loading overlay
          if (_isCapturing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 16),
                    Text(
                      '撮影中...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Era selector
                  GestureDetector(
                    onTap: () => EraSelector.show(
                      context,
                      current: _selectedEra,
                      onSelected: _onEraSelected,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedEra.label,
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
                  const SizedBox(height: 20),
                  // Shutter + settings row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
                        onPressed: widget.onResetServer,
                        tooltip: 'サーバー設定',
                      ),
                      // Shutter button
                      GestureDetector(
                        onTap: _isCapturing ? null : _onShutter,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isCapturing ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Balance
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Data class for Isolate transfer
class _CameraData {
  const _CameraData({
    required this.width,
    required this.height,
    required this.planes,
    required this.strides,
    required this.planeCount,
  });
  final int width;
  final int height;
  final List<Uint8List> planes;
  final List<int> strides;
  final int planeCount;
}

/// Isolate function: convert NV12/YUV420 camera data to JPEG
Uint8List? _encodeJpeg(_CameraData data) {
  final isNV12 = data.planeCount == 2;
  final width = data.width;
  final height = data.height;
  final yPlane = data.planes[0];
  final yRowStride = data.strides[0];
  final uvPlane = data.planes[1];
  final uvRowStride = data.strides[1];

  final image = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yValue = yPlane[y * yRowStride + x];
      int uValue, vValue;

      if (isNV12) {
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * 2;
        uValue = uvPlane[uvIndex];
        vValue = uvPlane[uvIndex + 1];
      } else {
        final uvPixelStride = data.planeCount > 2 ? 1 : 2;
        final vPlane = data.planes[2];
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        uValue = uvPlane[uvIndex];
        vValue = vPlane[uvIndex];
      }

      final r = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
      final g = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yValue + 1.732446 * (uValue - 128)).clamp(0, 255).toInt();

      image.setPixelRgb(x, y, r, g, b);
    }
  }

  // Resize to 384x384 (CoreML input size)
  final size = width < height ? width : height;
  final cx = (width - size) ~/ 2;
  final cy = (height - size) ~/ 2;
  final cropped = img.copyCrop(image, x: cx, y: cy, width: size, height: size);
  final resized = img.copyResize(cropped, width: 384, height: 384);

  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}
