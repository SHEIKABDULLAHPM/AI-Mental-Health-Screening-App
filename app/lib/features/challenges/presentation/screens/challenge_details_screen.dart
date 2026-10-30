import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Challenge details showing the server-derived status and progress. Progress
/// only ever advances from real activity in other features, never from a
/// "check in" tap here.
class ChallengeDetailsScreen extends StatefulWidget {
  const ChallengeDetailsScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  State<ChallengeDetailsScreen> createState() =>
      _ChallengeDetailsScreenState();
}

class _ChallengeDetailsScreenState extends State<ChallengeDetailsScreen> {
  bool _joinPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChallengeController>().loadDetails(widget.challengeId);
      }
    });
  }

  Future<void> _start(Challenge c) async {
    setState(() => _joinPending = true);
    try {
      final ctrl = context.read<ChallengeController>();
      await ctrl.startChallenge(c.id);
      if (!mounted) return;

      if (ctrl.error != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(ctrl.error!), backgroundColor: Theme.of(context).colorScheme.error),
          );
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Challenge started — you got this!')),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Failed to start challenge: $e'), backgroundColor: Theme.of(context).colorScheme.error),
          );
      }
    } finally {
      if (mounted) setState(() => _joinPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<ChallengeController>();
    final c = ctrl.currentChallenge;

    final String frequencyLabel = switch (c?.frequency) {
      'DAILY' => 'Daily',
      'WEEKLY' => 'Weekly',
      _ => 'Challenge',
    };

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
                      backgroundColor: _accent(theme, c).withValues(alpha: 0.16),
                      child: Icon(
                        c.isCompleted
                            ? Icons.emoji_events_rounded
                            : c.isExpired
                                ? Icons.timer_off_rounded
                                : Icons.flag_rounded,
                        color: _accent(theme, c),
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
                            '$frequencyLabel · ${c.points} pts',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(label: c.statusLabel, color: _accent(theme, c)),
                ),
                if (c.status == ChallengeStatus.inProgress ||
                    c.status == ChallengeStatus.active) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    c.streak > 0
                        ? '${c.streak}-day streak'
                        : 'Keep it up — progress counts real activity.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  c.description,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
                if (c.why != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    c.why!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
                if (c.personalizationReason != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Pill(
                    icon: Icons.auto_awesome_rounded,
                    text: 'Why this one: ${c.personalizationReason}',
                  ),
                ],
                // Category / difficulty / duration info
                if (c.category != null || c.difficulty != null || c.estimatedDuration != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _InfoRow(category: c.category, difficulty: c.difficulty, duration: c.estimatedDuration),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppProgressBar(
                  value: c.progressFraction,
                  valueText: '${c.progress}/${c.target}',
                  label: '$frequencyLabel target',
                ),
                const SizedBox(height: AppSpacing.lg),
                _RewardSummary(challenge: c),
                const SizedBox(height: AppSpacing.md),
                if (c.reward != null)
                  _Pill(
                    icon: Icons.redeem_rounded,
                    text: 'Reward: ${c.reward}',
                  ),
                const SizedBox(height: AppSpacing.lg),
                switch (c.status) {
                  ChallengeStatus.available => SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _joinPending ? null : () => _start(c),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: Text(
                          _joinPending ? 'Starting…' : 'Start this challenge',
                        ),
                      ),
                    ),
                  ChallengeStatus.expired => const SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: null,
                        child: Text('Challenge expired'),
                      ),
                    ),
                  ChallengeStatus.completed => const SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: null,
                        child: Text('Completed'),
                      ),
                    ),
                  ChallengeStatus.active ||
                  ChallengeStatus.inProgress => Column(
                    children: [
                      _progressBanner(theme, c),
                      if (c.isGameChallenge) ...[
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _launchGame(context, c),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play Game'),
                          ),
                        ),
                      ],
                    ],
                  ),
                },
              ],
            ),
    );
  }

  Widget _progressBanner(ThemeData theme, Challenge c) {
    final remaining = c.remaining;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _accent(theme, c).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_graph_rounded, color: _accent(theme, c)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              remaining <= 0
                  ? 'You have completed this challenge!'
                  : 'Complete it by doing real activities — each one counts automatically. $remaining to go.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Color _accent(ThemeData theme, Challenge c) {
    if (c.isCompleted) return theme.colorScheme.tertiary;
    if (c.isExpired) return theme.colorScheme.onSurfaceVariant;
    return theme.colorScheme.primary;
  }

  void _launchGame(BuildContext context, Challenge c) {
    // Route to the game picker which lets the user choose which game to play.
    // The challengeId is passed so results are submitted against the active challenge.
    context.push('/challenges/${c.id}/game');
  }
}

/// Info row showing category, difficulty, and estimated duration.
class _InfoRow extends StatelessWidget {
  const _InfoRow({this.category, this.difficulty, this.duration});

  final String? category;
  final String? difficulty;
  final String? duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (category != null) ...[
            Icon(Icons.category_rounded, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(category!, style: textStyle),
            const SizedBox(width: AppSpacing.md),
          ],
          if (difficulty != null) ...[
            Icon(Icons.signal_cellular_alt_rounded, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(difficulty!, style: textStyle),
            const SizedBox(width: AppSpacing.md),
          ],
          if (duration != null) ...[
            Icon(Icons.schedule_rounded, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(duration!, style: textStyle),
          ],
        ],
      ),
    );
  }
}

/// Compact informational pill used for personalization and rewards.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Reward / badge summary for the current challenge.
class _RewardSummary extends StatelessWidget {
  const _RewardSummary({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.emoji_events_rounded,
              color: theme.colorScheme.tertiary,
              size: 32,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challenge.isCompleted ? 'Completed' : 'Reward',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    challenge.isCompleted
                        ? '${challenge.points} points earned'
                        : 'Earn ${challenge.points} points on completion.',
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
    );
  }
}
