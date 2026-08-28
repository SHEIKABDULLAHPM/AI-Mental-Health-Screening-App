import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';

/// Card for one challenge in the challenges list.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    this.onTap,
  });

  final Challenge challenge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = challenge.isCompleted;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: completed
                      ? theme.colorScheme.tertiaryContainer
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  completed
                      ? Icons.emoji_events_rounded
                      : Icons.flag_rounded,
                  color: completed
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            challenge.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusBadge(
                          label: completed ? 'Done' : '${challenge.durationDays} days',
                          color: completed
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (!completed)
                      AppProgressBar(
                        value: challenge.progress,
                        label:
                            'Day ${challenge.currentDay} of ${challenge.durationDays}',
                      )
                    else
                      Text(
                        'Completed · ${challenge.points} pts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
