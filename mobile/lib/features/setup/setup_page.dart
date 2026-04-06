import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/server_config.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.onConfigured});

  final VoidCallback onConfigured;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8765');
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // mDNS discovery
  BonsoirDiscovery? _discovery;
  final List<_DiscoveredServer> _servers = [];
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    try {
      _discovery = BonsoirDiscovery(type: '_chrono-lens._tcp');
      await _discovery!.initialize();
      _discovery!.eventStream?.listen((event) async {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            await _discovery!.serviceResolver.resolveService(event.service);
          case BonsoirDiscoveryServiceResolvedEvent():
            final service = event.service;
            var host = service.host;
            final port = service.port;
            debugPrint('[SetupPage] Resolved: host=$host port=$port attrs=${service.attributes}');
            // Strip trailing dot from mDNS hostname if present
            if (host != null && host.endsWith('.')) {
              host = host.substring(0, host.length - 1);
            }
            if (host != null && host.isNotEmpty && mounted) {
              final resolvedHost = host; // promote to non-null
              setState(() {
                _servers.removeWhere((s) => s.host == resolvedHost && s.port == port);
                _servers.add(_DiscoveredServer(
                  host: resolvedHost,
                  port: port,
                  pipeline: service.attributes['pipeline'] ?? 'echo',
                ));
              });
            }
          default:
            break;
        }
      });
      await _discovery!.start();
    } catch (e) {
      debugPrint('[SetupPage] mDNS discovery failed: $e');
    }

    // Stop spinning after 5 seconds regardless
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _connectTo(String host, int port) async {
    await ServerConfig.save(host, port);
    if (mounted) widget.onConfigured();
  }

  Future<void> _saveManual() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final port = int.tryParse(_portController.text) ?? 8765;
    await ServerConfig.save(_hostController.text, port);
    if (mounted) widget.onConfigured();
  }

  @override
  void dispose() {
    _discovery?.stop();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    const Text(
                      'Chrono Lens',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Auto-discovered servers
                    _SectionLabel(
                      label: 'サーバーを検出中',
                      searching: _searching,
                    ),
                    const SizedBox(height: 12),
                    if (_servers.isNotEmpty)
                      ..._servers.map((s) => _ServerTile(
                            server: s,
                            onTap: () => _connectTo(s.host, s.port),
                          ))
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _searching
                              ? '同じWi-Fiでサーバーを起動してください…'
                              : '見つかりませんでした。手動で入力してください。',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Manual input (collapsed by default)
                    _ManualInputSection(
                      formKey: _formKey,
                      hostController: _hostController,
                      portController: _portController,
                      saving: _saving,
                      onSave: _saveManual,
                    ),

                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredServer {
  const _DiscoveredServer({
    required this.host,
    required this.port,
    required this.pipeline,
  });
  final String host;
  final int port;
  final String pipeline;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.searching});
  final String label;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        if (searching) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
          ),
        ],
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.onTap});
  final _DiscoveredServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.dns, color: Colors.amber, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${server.host}:${server.port}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        server.pipeline.toUpperCase(),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualInputSection extends StatefulWidget {
  const _ManualInputSection({
    required this.formKey,
    required this.hostController,
    required this.portController,
    required this.saving,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController hostController;
  final TextEditingController portController;
  final bool saving;
  final VoidCallback onSave;

  @override
  State<_ManualInputSection> createState() => _ManualInputSectionState();
}

class _ManualInputSectionState extends State<_ManualInputSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              const Text(
                '手動で入力',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(width: 4),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white38,
                size: 18,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          Form(
            key: widget.formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: widget.hostController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: _inputDecoration('192.168.1.xxx'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'IPを入力';
                    final parts = v.trim().split('.');
                    if (parts.length != 4) return '正しいIPv4形式';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: widget.portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: _inputDecoration('8765'),
                  validator: (v) {
                    final port = int.tryParse(v ?? '');
                    if (port == null || port < 1 || port > 65535) return '1〜65535';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: widget.saving ? null : widget.onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade600,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: widget.saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('接続する',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.amber.shade600, width: 2),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}
