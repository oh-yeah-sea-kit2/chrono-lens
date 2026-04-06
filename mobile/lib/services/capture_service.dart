import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
class CaptureService {
  CaptureService({required this.baseUrl});

  final String baseUrl;

  Future<CaptureResult> capture(Uint8List jpeg, Era era) async {
    final uri = Uri.parse('$baseUrl/capture');
    debugPrint('[Capture] POST $uri era=${era.id}');

    final request = http.MultipartRequest('POST', uri)
      ..fields['era_id'] = era.id.toString()
      ..fields['quality'] = 'high'
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        jpeg,
        filename: 'frame.jpg',
      ));

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Capture failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final imageBase64 = json['image'] as String;
    final imageBytes = base64Decode(imageBase64);

    return CaptureResult(
      image: Uint8List.fromList(imageBytes),
      eraId: json['era_id'] as int,
      processingTimeMs: json['processing_time_ms'] as int,
    );
  }
}
