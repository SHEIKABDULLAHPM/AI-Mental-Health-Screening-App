import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/habits/data/habit.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';

/// List card for one habit with a "done today" toggle.
class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.habit,
    required this.onToggle,
    this.onTap,
  });

  final Habit habit;
  final VoidCallback onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = habit.doneToday;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: habit.color.withValues(alpha: 0.15),
                child: Icon(habit.icon, color: habit.color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${habit.goalLabel} · ${habit.streak}-day streak',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: AppProgressBar(
                            value: habit.weekRate,
                            color: habit.color,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${habit.completedThisWeek}/7',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: done ? 'Mark not done' : 'Mark done',
                onPressed: onToggle,
                icon: done
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: habit.color,
                        size: 30,
                      )
                    : Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: theme.colorScheme.outline,
                        size: 30,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
