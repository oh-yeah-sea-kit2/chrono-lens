import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Smooth crossfade between the previous and current AI-generated frame.
/// Reduces perceived flicker significantly.
class CrossfadeRenderer extends StatefulWidget {
  const CrossfadeRenderer({
    super.key,
    required this.jpeg,
    this.fadeDuration = const Duration(milliseconds: 80),
    this.fit = BoxFit.cover,
  });

  final Uint8List jpeg;
  final Duration fadeDuration;
  final BoxFit fit;

  @override
  State<CrossfadeRenderer> createState() => _CrossfadeRendererState();
}

class _CrossfadeRendererState extends State<CrossfadeRenderer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  Uint8List? _prevJpeg;
  Uint8List? _currentJpeg;

  @override
  void initState() {
    super.initState();
    _currentJpeg = widget.jpeg;
    _controller = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
    )..value = 1.0;
    _opacity = _controller;
  }

  @override
  void didUpdateWidget(CrossfadeRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jpeg != oldWidget.jpeg) {
      _prevJpeg = _currentJpeg;
      _currentJpeg = widget.jpeg;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_prevJpeg != null)
          Image.memory(
            _prevJpeg!,
            fit: widget.fit,
            gaplessPlayback: true,
          ),
        AnimatedBuilder(
          animation: _opacity,
          builder: (context, child) => Opacity(
            opacity: _opacity.value,
            child: child,
          ),
          child: Image.memory(
            _currentJpeg!,
            fit: widget.fit,
            gaplessPlayback: true,
          ),
        ),
      ],
    );
  }
}
