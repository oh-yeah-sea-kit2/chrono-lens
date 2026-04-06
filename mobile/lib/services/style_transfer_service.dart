import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Communicates with the native CoreML StyleTransfer plugin via MethodChannel.
class StyleTransferService {
  static const _channel = MethodChannel('com.chrono_lens/style_transfer');

  bool _modelLoaded = false;
  bool _styleSet = false;
  bool get isReady => _modelLoaded && _styleSet;

  /// Load the CoreML model. Call once at startup.
  Future<bool> loadModel() async {
    try {
      final result = await _channel.invokeMethod<bool>('loadModel');
      _modelLoaded = result ?? false;
      debugPrint('[StyleTransfer] Model loaded: $_modelLoaded');
      return _modelLoaded;
    } on PlatformException catch (e) {
      debugPrint('[StyleTransfer] loadModel error: ${e.message}');
      _modelLoaded = false;
      return false;
    }
  }

  /// Set the style reference image. Call when era changes.
  /// [jpegData] is the style image encoded as JPEG.
  Future<bool> setStyle(Uint8List jpegData) async {
    try {
      final result = await _channel.invokeMethod<bool>('setStyle', {
        'jpeg': jpegData,
      });
      _styleSet = result ?? false;
      debugPrint('[StyleTransfer] Style set: $_styleSet');
      return _styleSet;
    } on PlatformException catch (e) {
      debugPrint('[StyleTransfer] setStyle error: ${e.message}');
      _styleSet = false;
      return false;
    }
  }

  /// Clear the style (passthrough mode).
  void clearStyle() {
    _styleSet = false;
  }

  /// Apply style transfer to a single JPEG frame.
  /// Returns stylized JPEG bytes, or null on failure.
  Future<Uint8List?> transferFrame(Uint8List jpegData, {int quality = 75}) async {
    if (!_modelLoaded) return null;
    if (!_styleSet) return jpegData; // passthrough

    try {
      final result = await _channel.invokeMethod<Uint8List>('transferFrame', {
        'jpeg': jpegData,
        'quality': quality,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('[StyleTransfer] transferFrame error: ${e.message}');
      return null;
    }
  }

  /// Check if native side is ready.
  Future<bool> checkReady() async {
    try {
      return await _channel.invokeMethod<bool>('isReady') ?? false;
    } catch (_) {
      return false;
    }
  }
}
