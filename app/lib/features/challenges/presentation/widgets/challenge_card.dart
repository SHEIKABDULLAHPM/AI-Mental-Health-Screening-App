import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';

/// Card for one challenge in the challenges list. Driven by server status and
/// progress; never by locally forged day counters.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    this.onTap,
  });

  final Challenge challenge;
  final VoidCallback? onTap;

  String get _frequencyLabel => switch (challenge.frequency) {
        'DAILY' => 'Daily',
        'WEEKLY' => 'Weekly',
        _ => 'Regular',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = challenge.isCompleted;
    final expired = challenge.isExpired;

    final Color accent;
    final IconData icon;
    if (completed) {
      accent = theme.colorScheme.tertiary;
      icon = Icons.emoji_events_rounded;
    } else if (expired) {
      accent = theme.colorScheme.onSurfaceVariant;
      icon = Icons.timer_off_rounded;
    } else {
      accent = theme.colorScheme.primary;
      icon = Icons.flag_rounded;
    }

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
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(icon, color: accent, size: 22),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusBadge(
                          label: completed
                              ? 'Done'
                              : expired
                                  ? 'Expired'
                                  : '$_frequencyLabel · ${challenge.points} pts',
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Category + difficulty row
                    Row(
                      children: [
                        if (challenge.category != null) ...[
                          Icon(Icons.category_rounded, size: 12, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            challenge.category!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (challenge.difficulty != null) ...[
                          Icon(Icons.signal_cellular_alt_rounded, size: 12, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            challenge.difficulty!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (challenge.estimatedDuration != null) ...[
                          Icon(Icons.schedule_rounded, size: 12, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            challenge.estimatedDuration!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (completed || expired)
                      Text(
                        completed
                            ? 'Completed · ${challenge.points} pts'
                            : 'This challenge is no longer available.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      AppProgressBar(
                        value: challenge.progressFraction,
                        valueText: '${challenge.progress}/${challenge.target}',
                        label: challenge.streak > 0
                            ? '${challenge.streak}-day streak · ${challenge.percentage}%'
                            : '${challenge.percentage}% complete',
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
