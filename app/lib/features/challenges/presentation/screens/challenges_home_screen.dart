import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/features/challenges/presentation/widgets/challenge_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Challenges hub: active + completed + earned badges.
class ChallengesHomeScreen extends StatefulWidget {
  const ChallengesHomeScreen({super.key});

  @override
  State<ChallengesHomeScreen> createState() => _ChallengesHomeScreenState();
}

class _ChallengesHomeScreenState extends State<ChallengesHomeScreen> {
  @override
  void initState() {
    super.initState();
    final ctrl = context.read<ChallengeController>();
    ctrl.loadActive();
    ctrl.loadCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<ChallengeController>();
    final active = ctrl.active;
    final completed = ctrl.completed;
    final allChallenges = [...active, ...completed];
    final points =
        completed.fold<int>(0, (sum, c) => sum + c.points);

    return FeatureScaffold(
      title: 'Challenges',
      body: ctrl.loading && allChallenges.isEmpty
          ? const LoadingView()
          : allChallenges.isEmpty
              ? const EmptyStateView(
                  icon: Icons.emoji_events_outlined,
                  title: 'No challenges yet',
                  message: 'New wellness challenges will appear here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events_rounded, size: 40),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$points points earned',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Keep going — streaks build over time.',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (active.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Active challenges'),
                      const SizedBox(height: AppSpacing.sm),
                      ...active.map(
                        (c) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ChallengeCard(
                            challenge: c,
                            onTap: () => context.push('/challenges/${c.id}'),
                          ),
                        ),
                      ),
                    ],
                    if (completed.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Completed'),
                      const SizedBox(height: AppSpacing.sm),
                      ...completed.map(
                        (c) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ChallengeCard(
                            challenge: c,
                            onTap: () => context.push('/challenges/${c.id}'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Badges'),
                    const SizedBox(height: AppSpacing.sm),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 1.6,
                      children: [
                        for (final badge in kChallengeBadges)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(badge.icon, color: theme.colorScheme.primary),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    badge.label,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
