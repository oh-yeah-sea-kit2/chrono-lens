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

/// Serializable snapshot of camera plane data.
class _PlaneData {
  _PlaneData({required this.bytes, required this.bytesPerRow, required this.bytesPerPixel});
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class _FrameSnapshot {
  _FrameSnapshot({
    required this.width,
    required this.height,
    required this.planes,
    required this.isYuv420,
    required this.isBgra,
  });
  final int width;
  final int height;
  final List<_PlaneData> planes;
  final bool isYuv420;
  final bool isBgra;
}

/// Ping-pong frame processor.
///
/// Flow:
/// 1. Server ready (or first frame) → capture & send ONE frame
/// 2. Wait for server result
/// 3. On result received → capture & send next frame
/// 4. Repeat
///
/// No frames are sent while the server is processing. Zero wasted frames.
class FrameProcessor {
  FrameProcessor();

  int _frameIdCounter = 0;

  /// true = server is processing, don't send
  /// false = server is idle, send next frame
  bool _inFlight = false;

  /// Set to true once the first frame has been sent.
  bool _started = false;

  // Stats
  int _sentCount = 0;
  int _skippedCount = 0;
  final List<double> _recentRttsMs = [];

  Era era = Era.taisho;

  /// Whether we should capture and send the next frame.
  bool get shouldSend => !_inFlight;

  /// Call when a server result arrives → unlocks sending the next frame.
  void onResultReceived(double rttMs) {
    _inFlight = false;
    _recentRttsMs.add(rttMs);
    if (_recentRttsMs.length > 20) _recentRttsMs.removeAt(0);
  }

  /// Process a camera frame. Returns binary data to send, or null if skipped.
  ///
  /// Only returns non-null when the server is ready for the next frame.
  Future<Uint8List?> process(CameraImage image) async {
    // Strict ping-pong: only one frame at a time.
    // Set _inFlight SYNCHRONOUSLY before any await to prevent race conditions.
    if (_started && _inFlight) {
      _skippedCount++;
      return null;
    }
    // Lock immediately — no other camera callback can slip through
    _inFlight = true;

    // Copy native camera data to Dart heap before Isolate
    final snapshot = _FrameSnapshot(
      width: image.width,
      height: image.height,
      planes: image.planes.map((p) => _PlaneData(
        bytes: Uint8List.fromList(p.bytes),
        bytesPerRow: p.bytesPerRow,
        bytesPerPixel: p.bytesPerPixel ?? 1,
      )).toList(),
      isYuv420: image.format.group == ImageFormatGroup.yuv420,
      isBgra: image.format.group == ImageFormatGroup.bgra8888,
    );

    final jpeg = await _encodeFrame(snapshot);
    if (jpeg == null) {
      _inFlight = false; // release lock on encode failure
      return null;
    }

    _frameIdCounter++;
    final frameId = _frameIdCounter;
    final tsUs = DateTime.now().microsecondsSinceEpoch;

    final raw = _buildBinaryFrame(
      frameId: frameId,
      clientTsUs: tsUs,
      eraId: era.id,
      jpeg: jpeg,
    );

    _started = true;
    _sentCount++;

    return raw;
  }

  Future<Uint8List?> _encodeFrame(_FrameSnapshot snapshot) async {
    try {
      return await compute(_convertAndEncode, snapshot);
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
    header.setUint8(25, 75);
    header.setUint16(26, 0, Endian.little);
    header.setUint32(28, jpeg.length, Endian.little);

    final result = Uint8List(32 + jpeg.length);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(32, jpeg);
    return result;
  }

  Map<String, dynamic> get stats => {
        'sent': _sentCount,
        'skipped': _skippedCount,
        'inFlight': _inFlight,
        'avgRttMs': _recentRttsMs.isEmpty
            ? 0
            : (_recentRttsMs.reduce((a, b) => a + b) / _recentRttsMs.length)
                .round(),
      };
}

/// Runs in an Isolate.
Uint8List? _convertAndEncode(_FrameSnapshot snap) {
  img.Image? frame;

  if (snap.isYuv420) {
    frame = _yuv420ToImage(snap);
  } else if (snap.isBgra) {
    frame = img.Image.fromBytes(
      width: snap.width,
      height: snap.height,
      bytes: snap.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  } else {
    return null;
  }

  final size = frame.width < frame.height ? frame.width : frame.height;
  final x = (frame.width - size) ~/ 2;
  final y = (frame.height - size) ~/ 2;
  final cropped = img.copyCrop(frame, x: x, y: y, width: size, height: size);
  final resized = img.copyResize(cropped, width: _targetSize, height: _targetSize);

  return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
}

img.Image _yuv420ToImage(_FrameSnapshot snap) {
  final width = snap.width;
  final height = snap.height;
  final yPlane = snap.planes[0].bytes;
  final yRowStride = snap.planes[0].bytesPerRow;
  final uvPlane = snap.planes[1].bytes;
  final uvRowStride = snap.planes[1].bytesPerRow;

  final isNV12 = snap.planes.length == 2;
  final Uint8List? vPlane = isNV12 ? null : snap.planes[2].bytes;
  final uvPixelStride = snap.planes[1].bytesPerPixel;

  final image = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yValue = yPlane[y * yRowStride + x];

      int uValue;
      int vValue;

      if (isNV12) {
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * 2;
        uValue = uvPlane[uvIndex];
        vValue = uvPlane[uvIndex + 1];
      } else {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        uValue = uvPlane[uvIndex];
        vValue = vPlane![uvIndex];
      }

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
