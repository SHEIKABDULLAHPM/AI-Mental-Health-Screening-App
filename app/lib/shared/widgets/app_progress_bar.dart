import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';

/// Labelled linear progress bar (e.g. challenge goal, habit completion).
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.max = 1.0,
    this.color,
    this.label,
    this.valueText,
    this.showPercent = false,
  });

  final double value;
  final double max;
  final Color? color;
  final String? label;
  final String? valueText;
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final percent = (fraction * 100).round();
    final accent = color ?? theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null || valueText != null || showPercent) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (label != null)
                Expanded(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                valueText ?? '$percent%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 10,
            color: accent,
            backgroundColor: accent.withValues(alpha: 0.14),
          ),
        ),
      ],
    );
  }
}

/// Compact badge used for streaks, rewards and status pills.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.color,
  });

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small square "step" cell used in habit/weekly grids.
class GridStep extends StatelessWidget {
  const GridStep({
    super.key,
    required this.done,
    this.today = false,
    this.color,
  });

  final bool done;
  final bool today;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: done
            ? accent
            : (today
                ? accent.withValues(alpha: 0.22)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
        border: today
            ? Border.all(color: accent, width: 1.6)
            : Border.all(color: Colors.transparent),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 14, color: theme.colorScheme.onPrimary)
          : null,
    );
  }
}
