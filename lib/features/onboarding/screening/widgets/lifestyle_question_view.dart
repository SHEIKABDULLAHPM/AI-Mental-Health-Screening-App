import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../data/questionnaires.dart';
import 'option_picker.dart';
import 'slider_field.dart';

class LifestyleQuestionView extends StatelessWidget {
  const LifestyleQuestionView({
    super.key,
    required this.question,
    required this.number,
    required this.total,
    required this.value,
    required this.onChanged,
    required this.onSelectChoice,
  });

  final LifestyleQuestion question;
  final int number;
  final int total;
  final double? value;
  final ValueChanged<double> onChanged;
  final ValueChanged<int> onSelectChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Lifestyle',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Question $number of $total',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        if (question.type == LifestyleInputType.slider)
          SliderField(
            title: question.title,
            hint: question.hint,
            value: value,
            onChanged: onChanged,
            min: question.min,
            max: question.max,
            step: question.step,
            unit: question.unit,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                question.hint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              OptionPicker(
                options: question.choices
                    .map((choice) => ScaleOption(choice.value, choice.label))
                    .toList(),
                selectedValue: value?.round(),
                onSelect: onSelectChoice,
              ),
            ],
          ),
      ],
    );
  }
}
