import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/frame_message.dart';

/// Server message header size in bytes.
const _serverHeaderSize = 40;

/// Magic bytes 'CL'
const _magic0 = 0x43;
const _magic1 = 0x4C;

enum WsState { disconnected, connecting, connected, reconnecting }

class WebSocketService extends ChangeNotifier {
  WebSocketService({required this.serverUrl});

  final String serverUrl;
  final _clientId = const Uuid().v4();

  WsState _state = WsState.disconnected;
  WsState get state => _state;

  final _resultController = StreamController<ResultMessage>.broadcast();
  Stream<ResultMessage> get resultStream => _resultController.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _reconnectDelay = 1;

  String? _sessionId;
  String? get sessionId => _sessionId;

  Future<void> connect() async {
    if (_state == WsState.connected || _state == WsState.connecting) return;
    _setState(WsState.connecting);
    _reconnectTimer?.cancel();

    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      // Send HELLO
      _channel!.sink.add(jsonEncode({
        'type': 'hello',
        'client_id': _clientId,
        'device_model': defaultTargetPlatform.name,
        'app_version': '0.1.0',
      }));

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _setState(WsState.connected);
      _reconnectDelay = 1;
    } catch (e) {
      debugPrint('[WS] connect failed: $e');
      _scheduleReconnect();
    }
  }

  void sendFrame(Uint8List frameBytes) {
    if (_state != WsState.connected) return;
    try {
      _channel?.sink.add(frameBytes);
    } catch (e) {
      debugPrint('[WS] send error: $e');
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is String) {
      // Control message (WELCOME etc.)
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      if (msg['type'] == 'welcome') {
        _sessionId = msg['session_id'] as String?;
        debugPrint('[WS] session=$_sessionId');
      }
      return;
    }

    if (raw is List<int>) {
      final bytes = Uint8List.fromList(raw);
      final result = _parseResult(bytes);
      if (result != null) {
        _resultController.add(result);
      }
    }
  }

  ResultMessage? _parseResult(Uint8List bytes) {
    if (bytes.length < _serverHeaderSize) return null;
    if (bytes[0] != _magic0 || bytes[1] != _magic1) return null;

    final bd = bytes.buffer.asByteData();
    final frameId = bd.getUint64(4, Endian.little);
    final clientTsUs = bd.getUint64(12, Endian.little);
    final serverTsUs = bd.getUint64(20, Endian.little);
    final procUs = bd.getUint32(28, Endian.little);
    final eraId = bd.getUint8(32);
    final flags = bd.getUint8(33);
    final payloadLen = bd.getUint32(36, Endian.little);

    if (bytes.length < _serverHeaderSize + payloadLen) return null;
    final jpeg = bytes.sublist(_serverHeaderSize, _serverHeaderSize + payloadLen);

    return ResultMessage(
      frameId: frameId,
      clientTsUs: clientTsUs,
      serverTsUs: serverTsUs,
      procUs: procUs,
      eraId: eraId,
      flags: flags,
      jpeg: jpeg,
    );
  }

  void _onError(Object error) {
    debugPrint('[WS] error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WS] connection closed');
    if (_state != WsState.disconnected) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _setState(WsState.reconnecting);
    _sub?.cancel();
    _channel?.sink.close();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _reconnectDelay = (_reconnectDelay * 2).clamp(1, 30);
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _setState(WsState.disconnected);
  }

  void _setState(WsState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _resultController.close();
    super.dispose();
  }
}
