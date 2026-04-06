import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/server_config.dart';

/// Shown on first launch (or when no server is configured).
/// User enters the PC's local IP address.
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

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final port = int.tryParse(_portController.text) ?? 8765;
    await ServerConfig.save(_hostController.text, port);

    if (mounted) widget.onConfigured();
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
                child: Form(
                  key: _formKey,
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
                const SizedBox(height: 8),
                Text(
                  '同じWi-FiにつないだPCの\nIPアドレスを入力してください',
                  style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: 48),
                _label('サーバーIP'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hostController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: _inputDecoration('192.168.1.xxx'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'IPを入力してください';
                    final parts = v.trim().split('.');
                    if (parts.length != 4) return '正しいIPv4形式で入力してください';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _label('ポート'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: _inputDecoration('8765'),
                  validator: (v) {
                    final port = int.tryParse(v ?? '');
                    if (port == null || port < 1 || port > 65535) {
                      return '1〜65535の数値を入力してください';
                    }
                    return null;
                  },
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade600,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '接続する',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 13),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.amber.shade600, width: 2),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      );
}
