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

/// Manages a persistent WebSocket connection and sends capture requests over it.
/// The connection is established on startup (like the old streaming architecture)
/// and kept alive. This avoids iOS local network permission issues that block
/// new TCP connections from Flutter.
class CaptureService {
  CaptureService({required this.serverWsUrl});

  final String serverWsUrl; // e.g. ws://192.168.1.234:8765/stream

  WebSocketChannel? _channel;
  bool _connected = false;
  Completer<CaptureResult>? _pendingCapture;

  /// Connect to the server. Call once on page init.
  Future<bool> connect() async {
    try {
      debugPrint('[Capture] Connecting to $serverWsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(serverWsUrl));
      await _channel!.ready;

      // Send hello handshake
      _channel!.sink.add(jsonEncode({
        'type': 'hello',
        'client_id': 'capture-client',
        'device_model': 'iPhone',
        'app_version': '0.2.0',
      }));

      // Listen for all messages
      _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('[Capture] WS error: $e');
          _connected = false;
        },
        onDone: () {
          debugPrint('[Capture] WS closed');
          _connected = false;
        },
      );

      _connected = true;
      debugPrint('[Capture] Connected');
      return true;
    } catch (e) {
      debugPrint('[Capture] Connect failed: $e');
      _connected = false;
      return false;
    }
  }

  void _onMessage(dynamic data) {
    if (data is String) {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'welcome') {
        debugPrint('[Capture] Welcome: session=${json['session_id']}');
        return;
      }

      if (type == 'capture_result') {
        debugPrint('[Capture] Capture result received: ${json['processing_time_ms']}ms');
        final completer = _pendingCapture;
        if (completer != null && !completer.isCompleted) {
          final imageBase64 = json['image'] as String;
          completer.complete(CaptureResult(
            image: Uint8List.fromList(base64Decode(imageBase64)),
            eraId: json['era_id'] as int,
            processingTimeMs: json['processing_time_ms'] as int,
          ));
        }
        return;
      }

      if (type == 'capture_error') {
        final completer = _pendingCapture;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(Exception(json['error']));
        }
        return;
      }
    }
  }

  bool get isConnected => _connected;

  /// Send a capture request over the existing WebSocket connection.
  Future<CaptureResult> capture(Uint8List jpeg, Era era) async {
    if (!_connected || _channel == null) {
      throw Exception('Not connected to server');
    }

    debugPrint('[Capture] Sending capture: era=${era.id} jpeg=${jpeg.length}B');

    _pendingCapture = Completer<CaptureResult>();

    // Send JSON command
    _channel!.sink.add(jsonEncode({
      'type': 'capture',
      'era_id': era.id,
      'jpeg_length': jpeg.length,
    }));

    // Send JPEG binary
    _channel!.sink.add(jpeg);

    return _pendingCapture!.future.timeout(const Duration(seconds: 30));
  }

  void dispose() {
    _channel?.sink.close();
  }
}
