import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Before/After comparison slider.
/// Drag left/right to reveal more of the before or after image.
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.before,
    required this.after,
  });

  final Uint8List before;
  final Uint8List after;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  double _sliderPosition = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final dividerX = width * _sliderPosition;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _sliderPosition = (details.localPosition.dx / width).clamp(0.0, 1.0);
            });
          },
          child: Stack(
            children: [
              // After (full)
              Positioned.fill(
                child: Image.memory(widget.after, fit: BoxFit.cover, gaplessPlayback: true),
              ),
              // Before (clipped)
              Positioned.fill(
                child: ClipRect(
                  clipper: _LeftClipper(dividerX),
                  child: Image.memory(widget.before, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
              // Divider line
              Positioned(
                left: dividerX - 1.5,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: Colors.white,
                ),
              ),
              // Handle
              Positioned(
                left: dividerX - 20,
                top: constraints.maxHeight / 2 - 20,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 8),
                    ],
                  ),
                  child: const Icon(Icons.compare_arrows, size: 20, color: Colors.black54),
                ),
              ),
              // Labels
              const Positioned(
                left: 12,
                bottom: 12,
                child: _Label('Before'),
              ),
              const Positioned(
                right: 12,
                bottom: 12,
                child: _Label('After'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.dividerX);
  final double dividerX;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, dividerX, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.dividerX != dividerX;
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
