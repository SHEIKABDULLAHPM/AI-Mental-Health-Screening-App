import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/relax/data/relax_activity.dart';
import 'package:mindease/features/relax/presentation/state/relax_controller.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Relax & Heal hub: categories of breathing, meditation, music and sounds.
class RelaxHomeScreen extends StatefulWidget {
  const RelaxHomeScreen({super.key});

  @override
  State<RelaxHomeScreen> createState() => _RelaxHomeScreenState();
}

class _RelaxHomeScreenState extends State<RelaxHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RelaxController>().loadActivities();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<RelaxController>();
    final activities = ctrl.activities;
    final quickStart = activities.isNotEmpty ? activities.first : null;

    return FeatureScaffold(
      title: 'Relax & Heal',
      body: ctrl.loading && activities.isEmpty
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                if (quickStart != null) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/relax/${quickStart.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.tertiary,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.air_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Take a moment',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${quickStart.title} · '
                              '${quickStart.duration.inMinutes} min',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: theme.colorScheme.primary,
                              ),
                              onPressed: () =>
                                  context.push('/relax/${quickStart.id}'),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start now'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final category in RelaxCategory.values)
                      ActionChip(
                        avatar: Icon(category.icon, size: 16),
                        label: Text(category.label),
                        onPressed: () {},
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final category in RelaxCategory.values)
                  if (_activitiesIn(category).isNotEmpty) ...[
                    SectionHeader(title: category.label),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 172,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _activitiesIn(category).length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final activity = _activitiesIn(category)[index];
                          return _ActivityCard(
                            activity: activity,
                            onTap: () =>
                                context.push('/relax/${activity.id}'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
              ],
            ),
    );
  }

  List<RelaxActivity> _activitiesIn(RelaxCategory category) {
    final ctrl = context.read<RelaxController>();
    return ctrl.activities.where((a) => a.category == category).toList();
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.onTap});

  final RelaxActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      theme.colorScheme.primaryContainer,
                  child: Icon(
                    activity.icon,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const Spacer(),
                Text(
                  activity.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(activity.duration),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours} hr';
    return '${d.inMinutes} min';
  }
}
