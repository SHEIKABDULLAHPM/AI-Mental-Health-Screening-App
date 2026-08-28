import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/recommendations/data/recommendation.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/features/recommendations/presentation/widgets/recommendation_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Recommendations hub: primary recommendation + categorized list.
class RecommendationsHomeScreen extends StatefulWidget {
  const RecommendationsHomeScreen({super.key});

  @override
  State<RecommendationsHomeScreen> createState() =>
      _RecommendationsHomeScreenState();
}

class _RecommendationsHomeScreenState extends State<RecommendationsHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RecommendationController>().loadRecommendations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RecommendationController>();
    final items = ctrl.recommendations;

    return FeatureScaffold(
      title: 'Recommendations',
      body: ctrl.loading && items.isEmpty
          ? const LoadingView()
          : items.isEmpty
              ? _EmptyView(
                  error: ctrl.error,
                  onRetry: () => ctrl.loadRecommendations(),
                )
              : RefreshIndicator(
                  onRefresh: () => ctrl.refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      // ── Primary recommendation
                      if (items.isNotEmpty) ...[
                        _PrimaryCard(recommendation: items.first),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // ── Remaining recommendations grouped by category
                      for (final category in RecommendationCategory.values)
                        if (items
                            .where(
                              (r) => r.category == category.name && r != items.first,
                            )
                            .isNotEmpty) ...[
                          _SectionHeader(title: category.label),
                          const SizedBox(height: AppSpacing.sm),
                          ...items
                              .where(
                                (r) => r.category == category.name && r != items.first,
                              )
                              .map(
                            (r) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: RecommendationCard(
                                recommendation: r,
                                onTap: () => _openDetail(context, r),
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
    );
  }

  void _openDetail(BuildContext context, Recommendation r) {
    // Record OPENED interaction (fire-and-forget)
    context.read<RecommendationController>().recordInteraction(r.id, 'OPENED');
    context.push('/recommendations/${r.id}');
  }
}

/// Hero card for the top recommendation.
class _PrimaryCard extends StatelessWidget {
  const _PrimaryCard({required this.recommendation});

  final Recommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = parseCategory(recommendation.category);

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context
              .read<RecommendationController>()
              .recordInteraction(recommendation.id, 'OPENED');
          context.push('/recommendations/${recommendation.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Recommended for you',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(cat.icon, color: theme.colorScheme.primary, size: 20),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                recommendation.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                recommendation.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              if (recommendation.reason != null &&
                  recommendation.reason!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    recommendation.reason!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (recommendation.duration != null) ...[
                    Icon(Icons.schedule_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      recommendation.duration!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  if (recommendation.difficulty != null) ...[
                    Icon(Icons.signal_cellular_alt_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      recommendation.difficulty!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: () {
                      context
                          .read<RecommendationController>()
                          .recordInteraction(recommendation.id, 'OPENED');
                      context.push('/recommendations/${recommendation.id}');
                    },
                    child: const Text('Open'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              error != null
                  ? 'Could not load recommendations'
                  : 'No recommendations yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error != null
                  ? 'Check your connection and try again.'
                  : 'Complete a mood check-in to get personalized suggestions tailored to how you feel.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (error != null)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              )
            else
              FilledButton.tonal(
                onPressed: () => context.push('/mood-checkin'),
                child: const Text('Check in with your mood'),
              ),
          ],
        ),
      ),
    );
  }
}
