import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

class SliderField extends StatelessWidget {
  const SliderField({
    super.key,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
  });

  final String title;
  final String hint;
  final double? value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final String unit;

  String _format(double v) {
    final isWhole = v == v.roundToDouble();
    return isWhole ? v.round().toString() : v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: value != null ? scheme.primary : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Column(
            children: [
              Text(
                value == null ? 'Drag to set' : '${_format(value!)} $unit',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: value == null
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Slider(
                value: (value ?? min + (max - min) / 2)
                    .clamp(min, max)
                    .toDouble(),
                min: min,
                max: max,
                divisions: ((max - min) / step).round(),
                label:
                    '${_format((value ?? min + (max - min) / 2).clamp(min, max).toDouble())} $unit',
                onChanged: onChanged,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_format(min)} $unit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${_format(max)} $unit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
