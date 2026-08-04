import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    this.size = 180,
    this.strokeWidth = 14,
    required this.center,
  });

  final double score;
  final double size;
  final double strokeWidth;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100).toDouble();
    final color = AppColors.scoreColor(clamped);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              score: clamped,
              trackColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              arcColor: color,
              strokeWidth: strokeWidth,
            ),
          ),
          center,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.score,
    required this.trackColor,
    required this.arcColor,
    required this.strokeWidth,
  });

  final double score;
  final Color trackColor;
  final Color arcColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final shader = SweepGradient(
      colors: [arcColor.withValues(alpha: 0.45), arcColor, arcColor],
      stops: const [0.0, 0.7, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    final sweep = (score / 100) * 2 * math.pi;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.score != score ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor;
}
