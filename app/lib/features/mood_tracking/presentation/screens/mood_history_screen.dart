import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/widgets/mood_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Full mood history grouped by day with statistics summary.
class MoodHistoryScreen extends StatefulWidget {
  const MoodHistoryScreen({super.key});

  @override
  State<MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}

class _MoodHistoryScreenState extends State<MoodHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final controller = context.read<MoodController>();
        controller.loadEntries();
        controller.loadStatistics();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<MoodController>(context);
    final entries = controller.entries;
    final loading = controller.loading;
    final stats = controller.statistics;

    final grouped = _groupByDate(entries);

    return FeatureScaffold(
      title: 'Mood History',
      actions: [
        IconButton(
          tooltip: 'Mood trends',
          onPressed: () => context.push('/mood-trends'),
          icon: const Icon(Icons.insights_rounded),
        ),
      ],
      body: loading
          ? const LoadingView()
          : controller.error != null
              ? EmptyStateView(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load history',
                  message: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () {
                    final c = context.read<MoodController>();
                    c.loadEntries();
                    c.loadStatistics();
                  },
                )
              : entries.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.history_rounded,
                      title: 'No moods recorded',
                      message:
                          'Your mood history will appear here once you start '
                          'logging how you feel.',
                    )
                  : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _HistorySummary(
                          totalEntries: entries.length,
                          stats: stats,
                        ),
                      ),
                    ),
                    ...grouped.entries.map((dayGroup) {
                      return SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        sliver: SliverMainAxisGroup(slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                                bottom: AppSpacing.sm,
                              ),
                              child: Text(
                                _formatDayHeader(dayGroup.key),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                          SliverList.builder(
                            itemCount: dayGroup.value.length,
                            itemBuilder: (context, index) {
                              final entry = dayGroup.value[index];
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: MoodEntryTile(
                                  entry: entry,
                                  onTap: () => context
                                      .push('/mood-detail/${entry.id}'),
                                ),
                              );
                            },
                          ),
                        ],),
                      );
                    }),
                    const SliverPadding(
                      padding: EdgeInsets.only(bottom: AppSpacing.lg),
                    ),
                  ],
                ),
    );
  }

  static Map<String, List<MoodEntry>> _groupByDate(List<MoodEntry> entries) {
    final map = <String, List<MoodEntry>>{};
    for (final e in entries) {
      final key =
          '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  static String _formatDayHeader(String dateKey) {
    final parts = dateKey.split('-');
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDay = DateTime(date.year, date.month, date.day);

    if (entryDay == today) return 'Today';
    if (entryDay == yesterday) return 'Yesterday';

    final months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final weekdays = [
      '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday',
    ];
    return '${weekdays[date.weekday]}, ${months[date.month]} ${date.day}';
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.totalEntries, this.stats});

  final int totalEntries;
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = stats?['currentStreak'] ?? 0;
    final longestStreak = stats?['longestStreak'] ?? 0;
    final avgIntensity = (stats?['averageIntensity'] ?? 0.0) as num;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SummaryItem(
              value: '$totalEntries',
              label: 'Total',
              icon: Icons.calendar_today_rounded,
            ),
            _SummaryItem(
              value: '$streak',
              label: 'Streak',
              icon: Icons.local_fire_department_rounded,
              color: Colors.orange,
            ),
            _SummaryItem(
              value: '$longestStreak',
              label: 'Best',
              icon: Icons.emoji_events_rounded,
              color: Colors.amber,
            ),
            _SummaryItem(
              value: avgIntensity.toStringAsFixed(1),
              label: 'Avg intensity',
              icon: Icons.speed_rounded,
              color: theme.colorScheme.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: accent),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
