import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';

/// A single point in a [TrendChart].
class TrendDatum {
  const TrendDatum(this.label, this.value, {this.color});

  final String label;
  final double value;
  final Color? color;
}

enum TrendChartKind { bar, line }

/// Lightweight dependency-free trend visualisation.
///
/// [bar]: rounded vertical bars (e.g. weekly mood counts, habit completions).
/// [line]: smooth line with a soft area fill (e.g. mood over a month).
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.data,
    required this.kind,
    this.height = 180,
    this.maxValue = 6,
    this.lineColor,
    this.axisLabelColor,
  });

  final List<TrendDatum> data;
  final TrendChartKind kind;
  final double height;
  final double maxValue;
  final Color? lineColor;
  final Color? axisLabelColor;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(height: 0);
    }
    final theme = Theme.of(context);
    final labelColor =
        axisLabelColor ?? theme.colorScheme.onSurfaceVariant;
    final effectiveMax = math.max(maxValue, data.fold(0.0, (m, d) => math.max(m, d.value)));

    return SizedBox(
      height: height,
      width: double.infinity,
      child: kind == TrendChartKind.bar
          ? CustomPaint(
              painter: _BarChartPainter(
                data: data,
                maxValue: effectiveMax,
                labelColor: labelColor,
                barColor: lineColor ?? theme.colorScheme.primary,
              ),
            )
          : CustomPaint(
              painter: _LineChartPainter(
                data: data,
                maxValue: effectiveMax,
                lineColor: lineColor ?? theme.colorScheme.primary,
                fillColor:
                    (lineColor ?? theme.colorScheme.primary).withValues(alpha: 0.14),
                labelColor: labelColor,
              ),
            ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.data,
    required this.maxValue,
    required this.labelColor,
    required this.barColor,
  });

  final List<TrendDatum> data;
  final double maxValue;
  final Color labelColor;
  final Color barColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 22.0;
    const topPad = 6.0;
    final plotHeight = size.height - bottomPad - topPad;
    final slot = size.width / data.length;
    final barWidth = math.min(slot * 0.5, 26.0);

    final labelStyle = TextStyle(
      color: labelColor,
      fontSize: 11,
      fontFamily: 'Inter',
    );

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final fraction = maxValue == 0 ? 0.0 : (d.value / maxValue).clamp(0.0, 1.0);
      final barHeight = plotHeight * fraction;
      final left = slot * i + (slot - barWidth) / 2;
      final top = topPad + (plotHeight - barHeight);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = d.color ?? barColor,
      );

      final tp = TextPainter(
        text: TextSpan(text: d.label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot);
      tp.paint(
        canvas,
        Offset(slot * i + (slot - tp.width) / 2, topPad + plotHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.maxValue != maxValue;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.data,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.labelColor,
  });

  final List<TrendDatum> data;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 22.0;
    const topPad = 8.0;
    final plotHeight = size.height - bottomPad - topPad;
    final slot = size.width / math.max(1, data.length - 1);

    Offset pointAt(int i) {
      final fraction =
          maxValue == 0 ? 0.0 : (data[i].value / maxValue).clamp(0.0, 1.0);
      return Offset(slot * i, topPad + (1 - fraction) * plotHeight);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < data.length; i++) {
      final p = pointAt(i);
      final prev = pointAt(i - 1);
      final midDx = (prev.dx + p.dx) / 2;
      path.cubicTo(midDx, prev.dy, midDx, p.dy, p.dx, p.dy);
    }

    final area = Path.from(path)
      ..lineTo(pointAt(data.length - 1).dx, size.height - bottomPad)
      ..lineTo(pointAt(0).dx, size.height - bottomPad)
      ..close();
    canvas.drawPath(area, Paint()..color = fillColor);

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final labelStyle = TextStyle(
      color: labelColor,
      fontSize: 11,
      fontFamily: 'Inter',
    );

    // Baseline plus the first/last/mid labels to keep the axis tidy.
    final labelIndexes = <int>{0, data.length ~/ 2, data.length - 1}.toList()..sort();
    for (final i in labelIndexes) {
      final tp = TextPainter(
        text: TextSpan(text: data[i].label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((pointAt(i).dx - tp.width / 2).clamp(0, size.width - tp.width), topPad + plotHeight + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.maxValue != maxValue;
}

/// Horizontal stacked distribution bar with a legend (e.g. mood distribution).
class DistributionBar extends StatelessWidget {
  const DistributionBar({
    super.key,
    required this.segments,
    this.height = 14,
  });

  /// (label, value, color) — values are normalised to 100% for rendering.
  final List<(String, double, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = segments.fold<double>(0, (sum, s) => sum + s.$2);
    final safeTotal = total <= 0 ? 1.0 : total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Row(
              children: [
                for (final (_, value, color) in segments)
                  if (value > 0)
                    Expanded(
                      flex: (value / safeTotal * 1000).round(),
                      child: Container(color: color),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (label, value, color) in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$label · ${(value / safeTotal * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
