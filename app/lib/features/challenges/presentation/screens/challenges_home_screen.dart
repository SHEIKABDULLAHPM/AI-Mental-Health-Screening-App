import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/features/challenges/presentation/widgets/challenge_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Challenges hub: recommended, active, completed, streak + points, badges.
class ChallengesHomeScreen extends StatefulWidget {
  const ChallengesHomeScreen({super.key});

  @override
  State<ChallengesHomeScreen> createState() => _ChallengesHomeScreenState();
}

class _ChallengesHomeScreenState extends State<ChallengesHomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ChallengeController>().loadHome();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<ChallengeController>();
    final active = ctrl.active;
    final completed = ctrl.completed;
    final badges = ctrl.badges;
    final recommended = ctrl.recommended;
    final hasContent = active.isNotEmpty ||
        completed.isNotEmpty ||
        recommended != null;

    return FeatureScaffold(
      title: 'Challenges',
      body: ctrl.loading && !ctrl.loaded
          ? const LoadingView()
          : ctrl.error != null && !ctrl.loaded
              ? ErrorStateView(
                  title: 'Could not load challenges',
                  message: ctrl.error!,
                  onRetry: () => ctrl.loadHome(),
                )
              : !hasContent && badges.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.emoji_events_outlined,
                      title: 'No challenges yet',
                      message: 'New wellness challenges will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => ctrl.loadHome(refresh: true),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        children: [
                          _SummaryCard(
                            currentStreak: ctrl.currentStreak,
                            pointsEarned: ctrl.pointsEarned,
                          ),
                          if (recommended != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            const SectionHeader(title: 'Recommended for you'),
                            const SizedBox(height: AppSpacing.sm),
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: ChallengeCard(
                                challenge: recommended,
                                onTap: () => context
                                    .push('/challenges/${recommended.id}'),
                              ),
                            ),
                          ],
                          if (active.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            const SectionHeader(title: 'In progress'),
                            const SizedBox(height: AppSpacing.sm),
                            ...active.map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: ChallengeCard(
                                  challenge: c,
                                  onTap: () =>
                                      context.push('/challenges/${c.id}'),
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
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: ChallengeCard(
                                  challenge: c,
                                  onTap: () =>
                                      context.push('/challenges/${c.id}'),
                                ),
                              ),
                            ),
                          ],
                          // Play Games link
                          if (active.isNotEmpty || recommended != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => context.push('/challenges/games'),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                        ),
                                        child: Icon(
                                          Icons.videogame_asset_rounded,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Play Games',
                                              style: theme.textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              'Boost focus with 2048, Sudoku, and more.',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (badges.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            const SectionHeader(title: 'Badges'),
                            const SizedBox(height: AppSpacing.sm),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: AppSpacing.sm,
                              crossAxisSpacing: AppSpacing.sm,
                              childAspectRatio: 1.7,
                              children: [
                                for (final badge in badges)
                                  Card(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.md),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            badge.icon,
                                            color: theme.colorScheme.primary,
                                            size: 28,
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.sm,
                                          ),
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
                          // History link
                          if (completed.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Center(
                              child: TextButton.icon(
                                onPressed: () => context.push('/challenges/history'),
                                icon: const Icon(Icons.history_rounded, size: 20),
                                label: const Text('View Challenge History'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

/// Streak + points summary card at the top of the home screen.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.currentStreak, required this.pointsEarned});

  final int currentStreak;
  final int pointsEarned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
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
                    '$pointsEarned points earned',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currentStreak > 0
                        ? '$currentStreak-day current streak — keep going!'
                        : 'Keep going — streaks build over time.',
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
