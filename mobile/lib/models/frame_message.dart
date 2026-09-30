import 'dart:typed_data';

/// Parsed result received from the server.
class ResultMessage {
  ResultMessage({
    required this.frameId,
    required this.clientTsUs,
    required this.serverTsUs,
    required this.procUs,
    required this.eraId,
    required this.flags,
    required this.jpeg,
  }) : receivedTsUs = DateTime.now().microsecondsSinceEpoch;

  final int frameId;
  final int clientTsUs;
  final int serverTsUs;
  final int procUs;
  final int eraId;
  final int flags;
  final Uint8List jpeg;

  /// Timestamp when this result was received on the client (set at parse time).
  final int receivedTsUs;

  bool get isDropped => (flags & 0x01) != 0;

  /// Round-trip time in milliseconds: receive time − send time.
  double get rttMs => (receivedTsUs - clientTsUs) / 1000.0;

  double get procMs => procUs / 1000.0;
}
