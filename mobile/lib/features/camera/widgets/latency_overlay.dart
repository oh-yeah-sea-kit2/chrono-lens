import 'package:flutter/material.dart';

/// Debug overlay showing RTT, proc time, and FPS stats.
class LatencyOverlay extends StatelessWidget {
  const LatencyOverlay({
    super.key,
    required this.rttMs,
    required this.procMs,
    required this.stats,
  });

  final double rttMs;
  final double procMs;
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 60,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()],
            fontFamily: 'monospace',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RTT  ${rttMs.toStringAsFixed(0).padLeft(5)} ms'),
              Text('Proc ${procMs.toStringAsFixed(0).padLeft(5)} ms'),
              Text('Sent ${stats['sent'].toString().padLeft(5)}'),
              Text('Skip ${stats['skipped'].toString().padLeft(5)}'),
              Text('Wait ${stats['inFlight'] == true ? '  YES' : '   NO'}'),
            ],
          ),
        ),
      ),
    );
  }
}
