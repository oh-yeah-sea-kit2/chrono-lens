import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
/// Uses dart:io HttpClient directly (Flutter's http package has issues
/// with local network connections on iOS).
class CaptureService {
  CaptureService({required this.baseUrl});

  final String baseUrl;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);

  Future<CaptureResult> capture(Uint8List jpeg, Era era) async {
    final uri = Uri.parse('$baseUrl/capture');
    debugPrint('[Capture] POST $uri era=${era.id} jpeg=${jpeg.length}B');

    // Build multipart/form-data body manually
    final boundary = '----ChronoLens${DateTime.now().millisecondsSinceEpoch}';
    final bodyParts = <List<int>>[];

    // era_id field
    bodyParts.add(utf8.encode('--$boundary\r\n'));
    bodyParts.add(utf8.encode('Content-Disposition: form-data; name="era_id"\r\n\r\n'));
    bodyParts.add(utf8.encode('${era.id}\r\n'));

    // quality field
    bodyParts.add(utf8.encode('--$boundary\r\n'));
    bodyParts.add(utf8.encode('Content-Disposition: form-data; name="quality"\r\n\r\n'));
    bodyParts.add(utf8.encode('high\r\n'));

    // image file
    bodyParts.add(utf8.encode('--$boundary\r\n'));
    bodyParts.add(utf8.encode('Content-Disposition: form-data; name="image"; filename="frame.jpg"\r\n'));
    bodyParts.add(utf8.encode('Content-Type: image/jpeg\r\n\r\n'));
    bodyParts.add(jpeg);
    bodyParts.add(utf8.encode('\r\n'));

    // End boundary
    bodyParts.add(utf8.encode('--$boundary--\r\n'));

    final body = bodyParts.expand((e) => e).toList();

    try {
      final request = await _client.postUrl(uri);
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(const Duration(seconds: 30));
      final responseBody = await response.transform(utf8.decoder).join();

      debugPrint('[Capture] Response: ${response.statusCode} (${responseBody.length} chars)');

      if (response.statusCode != 200) {
        throw Exception('Capture failed: ${response.statusCode} $responseBody');
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final imageBase64 = json['image'] as String;
      final imageBytes = base64Decode(imageBase64);

      return CaptureResult(
        image: Uint8List.fromList(imageBytes),
        eraId: json['era_id'] as int,
        processingTimeMs: json['processing_time_ms'] as int,
      );
    } on SocketException catch (e) {
      debugPrint('[Capture] SocketException: $e');
      rethrow;
    }
  }
}
