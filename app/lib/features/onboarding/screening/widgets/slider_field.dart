import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';

/// Big labelled slider with live value read-out.
class SliderField extends StatelessWidget {
  const SliderField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 12,
    this.step = 0.5,
    this.unit = '',
    this.hint,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final String unit;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display =
        value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your selection',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              unit.isEmpty ? display : '$display $unit',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          label: '$display $unit',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
