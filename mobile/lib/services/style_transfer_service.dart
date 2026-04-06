import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Communicates with the native CIFilter-based era style plugin.
/// No ML model needed — uses Core Image filters built into iOS.
class StyleTransferService {
  static const _channel = MethodChannel('com.chrono_lens/style_transfer');

  bool _ready = false;
  bool get isReady => _ready;

  int _currentEraId = 0;

  /// Initialize. Always succeeds (no model to load).
  Future<bool> loadModel() async {
    try {
      final result = await _channel.invokeMethod<bool>('loadModel');
      _ready = result ?? false;
      return _ready;
    } on PlatformException catch (e) {
      debugPrint('[StyleTransfer] init error: ${e.message}');
      return false;
    }
  }

  /// Set the current era by ID. CIFilter chain is selected on native side.
  Future<bool> setStyle(int eraId) async {
    try {
      _currentEraId = eraId;
      final result = await _channel.invokeMethod<bool>('setStyle', {
        'eraId': eraId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[StyleTransfer] setStyle error: ${e.message}');
      return false;
    }
  }

  /// Clear the style (passthrough mode).
  void clearStyle() {
    _currentEraId = 0;
  }

  /// Apply era filter to a single JPEG frame.
  /// Returns filtered JPEG bytes, or null on failure.
  Future<Uint8List?> transferFrame(Uint8List jpegData, {int quality = 75}) async {
    if (!_ready) return null;
    if (_currentEraId == 0) return jpegData; // passthrough

    try {
      final result = await _channel.invokeMethod<Uint8List>('transferFrame', {
        'jpeg': jpegData,
        'eraId': _currentEraId,
        'quality': quality,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('[StyleTransfer] transferFrame error: ${e.message}');
      return null;
    }
  }
}
