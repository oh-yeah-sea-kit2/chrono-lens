import 'package:shared_preferences/shared_preferences.dart';

const _kServerHostKey = 'server_host';
const _kServerPortKey = 'server_port';
const _defaultPort = 8765;

class ServerConfig {
  const ServerConfig({required this.host, required this.port});

  final String host;
  final int port;

  String get wsUrl => 'ws://$host:$port/stream';
  String get httpUrl => 'http://$host:$port';

  static final _ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

  static Future<ServerConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_kServerHostKey);
    if (host == null || host.isEmpty) return null;
    // Reject cached mDNS hostnames (e.g. "chrono-lens._chrono-lens._tcp.local.")
    // Only accept IP addresses
    if (!_ipRegex.hasMatch(host)) {
      await clear();
      return null;
    }
    final port = prefs.getInt(_kServerPortKey) ?? _defaultPort;
    return ServerConfig(host: host, port: port);
  }

  static Future<void> save(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerHostKey, host.trim());
    await prefs.setInt(_kServerPortKey, port);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kServerHostKey);
    await prefs.remove(_kServerPortKey);
  }
}
