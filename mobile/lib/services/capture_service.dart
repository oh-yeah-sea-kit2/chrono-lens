import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/era.dart';

class CaptureResult {
  const CaptureResult({
    required this.image,
    required this.eraId,
    required this.processingTimeMs,
  });

  final Uint8List image;
  final int eraId;
  final int processingTimeMs;
}

/// Sends a single frame to the server for high-quality AI transformation.
/// Uses native iOS URLSession via Platform Channel (dart:io sockets are
/// blocked by iOS local network restrictions, but URLSession works like Safari).
class CaptureService {
  CaptureService({required this.captureUrl});

  static const _channel = MethodChannel('com.chrono_lens/style_transfer');

  final String captureUrl; // e.g. http://192.168.1.234:8765/capture

  Future<CaptureResult> capture(Uint8List jpeg, Era era) async {
    debugPrint('[Capture] captureRemote: $captureUrl era=${era.id} jpeg=${jpeg.length}B');

    try {
      final jsonStr = await _channel.invokeMethod<String>('captureRemote', {
        'jpeg': jpeg,
        'url': captureUrl,
        'eraId': era.id,
      });

      if (jsonStr == null || jsonStr.isEmpty) {
        throw Exception('Empty response from server');
      }

      debugPrint('[Capture] Response received: ${jsonStr.length} chars');

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final imageBase64 = json['image'] as String;
      final imageBytes = base64Decode(imageBase64);

      return CaptureResult(
        image: Uint8List.fromList(imageBytes),
        eraId: json['era_id'] as int,
        processingTimeMs: json['processing_time_ms'] as int,
      );
    } on PlatformException catch (e) {
      debugPrint('[Capture] PlatformException: ${e.code} ${e.message}');
      rethrow;
    }
  }
}
