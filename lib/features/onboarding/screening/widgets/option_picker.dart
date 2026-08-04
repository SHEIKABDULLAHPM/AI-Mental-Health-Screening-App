import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../data/questionnaires.dart';

class OptionPicker extends StatelessWidget {
  const OptionPicker({
    super.key,
    required this.options,
    required this.onSelect,
    this.selectedValue,
  });

  final List<ScaleOption> options;
  final ValueChanged<int> onSelect;
  final int? selectedValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: options.map((option) {
        final selected = option.value == selectedValue;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.5)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.14),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelect(option.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? scheme.primary : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Text(
                          option.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
