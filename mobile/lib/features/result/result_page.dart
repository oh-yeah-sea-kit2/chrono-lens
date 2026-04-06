import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/era.dart';
import '../../services/capture_service.dart';
import 'widgets/compare_slider.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.originalJpeg,
    required this.era,
    required this.captureService,
    this.styledPreview,
  });

  final Uint8List originalJpeg;
  final Era era;
  final CaptureService captureService;
  final Uint8List? styledPreview;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  Uint8List? _result;
  bool _loading = true;
  String? _error;
  int _processingTimeMs = 0;

  @override
  void initState() {
    super.initState();
    _requestCapture();
  }

  Future<void> _requestCapture() async {
    try {
      final result = await widget.captureService.capture(
        widget.originalJpeg,
        widget.era,
      );
      if (mounted) {
        setState(() {
          _result = result.image;
          _processingTimeMs = result.processingTimeMs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final image = _result;
    if (image == null) return;

    try {
      await ImageGallerySaverPlus.saveImage(image, quality: 95, name: 'chrono_lens_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カメラロールに保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗: $e')),
        );
      }
    }
  }

  Future<void> _share() async {
    final image = _result;
    if (image == null) return;

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/chrono_lens_share.jpg');
      await file.writeAsBytes(image);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      debugPrint('[ResultPage] Share error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.era.label),
        actions: [
          if (_result != null) ...[
            IconButton(
              icon: const Icon(Icons.save_alt),
              onPressed: _save,
              tooltip: '保存',
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _share,
              tooltip: '共有',
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Loading state: show styled preview or original with spinner
    if (_loading) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            widget.styledPreview ?? widget.originalJpeg,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          Container(color: Colors.black38),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.amber),
                const SizedBox(height: 16),
                Text(
                  'AI変換中...',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.era.label,
                  style: TextStyle(color: Colors.amber.shade300, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Error state
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                '変換に失敗しました',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _requestCapture();
                },
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }

    // Success: Before/After comparison
    return Column(
      children: [
        Expanded(
          child: CompareSlider(
            before: widget.originalJpeg,
            after: _result!,
          ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '処理時間: ${(_processingTimeMs / 1000).toStringAsFixed(1)}秒',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
