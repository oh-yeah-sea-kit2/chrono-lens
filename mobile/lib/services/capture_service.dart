import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

/// Sends a single frame to the server for high-quality AI transformation
/// via a dedicated WebSocket connection (HTTP POST is blocked by iOS
/// local network restrictions on Flutter apps).
class CaptureService {
  CaptureService({required this.wsUrl});

  final String wsUrl; // e.g. ws://192.168.1.234:8765/capture_ws

  Future<CaptureResult> capture(Uint8List jpeg, Era era) async {
    debugPrint('[Capture] Connecting to $wsUrl');

    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await channel.ready;
    debugPrint('[Capture] Connected. Sending capture request: era=${era.id} jpeg=${jpeg.length}B');

    // Send JSON command first
    channel.sink.add(jsonEncode({
      'type': 'capture',
      'era_id': era.id,
    }));

    // Then send JPEG as binary
    channel.sink.add(jpeg);

    // Wait for JSON response
    final completer = Completer<CaptureResult>();
    late StreamSubscription sub;

    sub = channel.stream.listen(
      (data) {
        if (data is String) {
          debugPrint('[Capture] Response received: ${data.length} chars');
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (json.containsKey('error')) {
              completer.completeError(Exception(json['error']));
            } else {
              final imageBase64 = json['image'] as String;
              final imageBytes = base64Decode(imageBase64);
              completer.complete(CaptureResult(
                image: Uint8List.fromList(imageBytes),
                eraId: json['era_id'] as int,
                processingTimeMs: json['processing_time_ms'] as int,
              ));
            }
          } catch (e) {
            completer.completeError(e);
          }
          sub.cancel();
          channel.sink.close();
        }
      },
      onError: (e) {
        debugPrint('[Capture] WS error: $e');
        if (!completer.isCompleted) completer.completeError(e);
        sub.cancel();
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('WebSocket closed before response'));
        }
      },
    );

    return completer.future.timeout(const Duration(seconds: 30));
  }
}
