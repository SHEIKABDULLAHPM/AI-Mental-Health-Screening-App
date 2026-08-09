import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular progress arc painter used by score & progress visuals.
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    this.minValue = 0,
    this.maxValue = 100,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double minValue;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.11;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final fraction =
        ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
    final arc = Path()..addArc(rect, -math.pi / 2, 2 * math.pi * fraction);
    canvas.drawPath(
      arc,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
