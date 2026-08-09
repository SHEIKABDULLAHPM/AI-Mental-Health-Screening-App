import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_colors.dart';

/// Brand logo mark: a calm wellness orb with closed eyes and a spark.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoMarkPainter(),
    );
  }
}

/// Splash / auth header logo with wordmark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 56, this.showTagline = false});

  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogoMark(size: size),
        const SizedBox(height: 14),
        Text(
          'MindEase',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 6),
          Text(
            'Breathe. Understand. Thrive.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: s / 2);

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.gradientStart, AppColors.gradientAccent],
      ).createShader(rect);
    canvas.drawCircle(center, s / 2, bgPaint);

    final soft = Paint()..color = const Color(0x33FFFFFF);
    canvas.drawCircle(
      Offset(center.dx - s * 0.2, center.dy - s * 0.28),
      s * 0.22,
      soft,
    );

    final eye = Paint()
      ..color = Colors.white
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(center.dx - s * 0.18, center.dy + s * 0.02),
          width: s * 0.16,
          height: s * 0.16,),
      0.15 * 3.14159,
      3.14159 * 0.70,
      false,
      eye,
    );
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(center.dx + s * 0.18, center.dy + s * 0.02),
          width: s * 0.16,
          height: s * 0.16,),
      0.15 * 3.14159,
      3.14159 * 0.70,
      false,
      eye,
    );

    final mouth = Paint()
      ..color = Colors.white
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(center.dx, center.dy + s * 0.24),
          width: s * 0.24,
          height: s * 0.18,),
      0.1 * 3.14159,
      3.14159 * 0.80,
      false,
      mouth,
    );

    _drawSpark(canvas, center + Offset(s * 0.32, -s * 0.34), s * 0.10);

    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, s / 2 - 1, rim);
  }

  void _drawSpark(Canvas canvas, Offset at, double r) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(at.dx, at.dy - r)
      ..quadraticBezierTo(at.dx + r * 0.28, at.dy - r * 0.28, at.dx + r, at.dy)
      ..quadraticBezierTo(at.dx + r * 0.28, at.dy + r * 0.28, at.dx, at.dy + r)
      ..quadraticBezierTo(at.dx - r * 0.28, at.dy + r * 0.28, at.dx - r, at.dy)
      ..quadraticBezierTo(at.dx - r * 0.28, at.dy - r * 0.28, at.dx, at.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) => false;
}
