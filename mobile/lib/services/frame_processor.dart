import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/era.dart';

/// Binary protocol constants.
const _magic = [0x43, 0x4C];
const _version = 0x01;
const _msgTypeFrame = 0x01;
const _targetSize = 512;

/// Controls camera frame → WebSocket binary conversion and throttling.
class FrameProcessor {
  FrameProcessor({
    int targetFps = 5,
    int maxInFlightMs = 300,
  })  : _targetIntervalMs = (1000 / targetFps).round(),
        _maxInFlightMs = maxInFlightMs;

  final int _targetIntervalMs;
  final int _maxInFlightMs;

  int _frameIdCounter = 0;
  int _lastSentMs = 0;
  bool _inFlight = false;
  int _inFlightSentMs = 0;

  // Stats
  int _sentCount = 0;
  int _droppedCount = 0;
  final List<double> _recentRttsMs = [];

  Era era = Era.taisho;

  /// Call when a server result arrives (releases backpressure).
  void onResultReceived(double rttMs) {
    _inFlight = false;
    _recentRttsMs.add(rttMs);
    if (_recentRttsMs.length > 10) _recentRttsMs.removeAt(0);

    // Adaptive FPS: slow down if server is struggling
    // (handled by backpressure naturally; no extra action needed here)
  }

  /// Returns encoded binary frame ready to send, or null if throttled.
  Future<Uint8List?> process(CameraImage image) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Throttle by target interval
    if (nowMs - _lastSentMs < _targetIntervalMs) {
      _droppedCount++;
      return null;
    }

    // Backpressure: wait for previous frame unless timeout exceeded
    if (_inFlight && nowMs - _inFlightSentMs < _maxInFlightMs) {
      _droppedCount++;
      return null;
    }

    final jpeg = await _encodeFrame(image);
    if (jpeg == null) return null;

    _frameIdCounter++;
    final frameId = _frameIdCounter;
    final tsUs = DateTime.now().microsecondsSinceEpoch;

    final raw = _buildBinaryFrame(
      frameId: frameId,
      clientTsUs: tsUs,
      eraId: era.id,
      jpeg: jpeg,
    );

    _lastSentMs = nowMs;
    _inFlight = true;
    _inFlightSentMs = nowMs;
    _sentCount++;

    return raw;
  }

  Future<Uint8List?> _encodeFrame(CameraImage image) async {
    try {
      return await compute(_convertAndEncodeIsolate, image);
    } catch (e) {
      debugPrint('[FrameProcessor] encode error: $e');
      return null;
    }
  }

  Uint8List _buildBinaryFrame({
    required int frameId,
    required int clientTsUs,
    required int eraId,
    required Uint8List jpeg,
  }) {
    // Header: 32 bytes (little-endian)
    final header = ByteData(32);
    header.setUint8(0, _magic[0]);
    header.setUint8(1, _magic[1]);
    header.setUint8(2, _version);
    header.setUint8(3, _msgTypeFrame);
    header.setUint64(4, frameId, Endian.little);
    header.setUint64(12, clientTsUs, Endian.little);
    header.setUint16(20, _targetSize, Endian.little);
    header.setUint16(22, _targetSize, Endian.little);
    header.setUint8(24, eraId);
    header.setUint8(25, 75); // JPEG quality hint
    header.setUint16(26, 0, Endian.little); // reserved
    header.setUint32(28, jpeg.length, Endian.little);

    final result = Uint8List(32 + jpeg.length);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(32, jpeg);
    return result;
  }

  Map<String, int> get stats => {
        'sent': _sentCount,
        'dropped': _droppedCount,
        'avgRttMs': _recentRttsMs.isEmpty
            ? 0
            : (_recentRttsMs.reduce((a, b) => a + b) / _recentRttsMs.length)
                .round(),
      };
}

/// Run in an Isolate to avoid blocking the UI thread.
Uint8List? _convertAndEncodeIsolate(CameraImage cameraImage) {
  img.Image? frame;

  if (cameraImage.format.group == ImageFormatGroup.yuv420) {
    frame = _yuv420ToImage(cameraImage);
  } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
    frame = img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: cameraImage.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  } else {
    return null;
  }

  // Center-crop to square then resize to 512x512
  final size = frame.width < frame.height ? frame.width : frame.height;
  final x = (frame.width - size) ~/ 2;
  final y = (frame.height - size) ~/ 2;
  final cropped = img.copyCrop(frame, x: x, y: y, width: size, height: size);
  final resized = img.copyResize(cropped, width: _targetSize, height: _targetSize);

  return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
}

img.Image _yuv420ToImage(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;
  final yPlane = cameraImage.planes[0].bytes;
  final uPlane = cameraImage.planes[1].bytes;
  final vPlane = cameraImage.planes[2].bytes;
  final uvRowStride = cameraImage.planes[1].bytesPerRow;
  final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

  final image = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yValue = yPlane[y * width + x];
      final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
      final uValue = uPlane[uvIndex];
      final vValue = vPlane[uvIndex];

      final r = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
      final g = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yValue + 1.732446 * (uValue - 128)).clamp(0, 255).toInt();

      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}
