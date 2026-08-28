import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Challenge details with day-by-day progress + badge preview.
class ChallengeDetailsScreen extends StatefulWidget {
  const ChallengeDetailsScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  State<ChallengeDetailsScreen> createState() =>
      _ChallengeDetailsScreenState();
}

class _ChallengeDetailsScreenState extends State<ChallengeDetailsScreen> {
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChallengeController>().loadDetails(widget.challengeId);
      }
    });
  }

  void _toggleDay(Challenge c) {
    context.read<ChallengeController>().updateProgress(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<ChallengeController>();
    final c = ctrl.currentChallenge;
    return FeatureScaffold(
      title: 'Challenge',
      body: ctrl.loading || c == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        c.isCompleted
                            ? Icons.emoji_events_rounded
                            : Icons.flag_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${c.durationDays} days · ${c.points} pts',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  c.description,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!c.isCompleted) ...[
                  AppProgressBar(
                    value: c.progress,
                    label: 'Day ${c.currentDay} of ${c.durationDays}',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: c.currentDay >= c.durationDays
                              ? null
                              : () => _toggleDay(c),
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            c.currentDay >= c.durationDays
                                ? 'Challenge complete!'
                                : 'Check in today',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Day-by-day',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var day = 1; day <= c.durationDays; day++)
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: GridStep(
                            done: day <= c.currentDay,
                            today: day == c.currentDay + 1,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Badge preview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          kChallengeBadges.last.icon,
                          color: theme.colorScheme.tertiary,
                          size: 32,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.isCompleted ? 'Completed' : 'Not earned yet',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Finish every day to earn this badge and its points.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!_joined && !c.isCompleted)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ctrl.startChallenge(c.id);
                        setState(() => _joined = true);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Challenge joined — let us go!'),
                            ),
                          );
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('Join this challenge'),
                    ),
                  ),
              ],
            ),
    );
  }
}
