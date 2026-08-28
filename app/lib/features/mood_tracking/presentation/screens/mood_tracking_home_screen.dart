import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/camera_mood_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/widgets/mood_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';
import 'package:mindease/shared/widgets/trend_chart.dart';

/// Mood Tracking home: today's mood, quick stats, recent entries and a
/// trend preview.
class MoodTrackingHomeScreen extends StatefulWidget {
  const MoodTrackingHomeScreen({super.key});

  @override
  State<MoodTrackingHomeScreen> createState() => _MoodTrackingHomeScreenState();
}

class _MoodTrackingHomeScreenState extends State<MoodTrackingHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final controller = context.read<MoodController>();
        controller.loadEntries();
        controller.loadRecentEntries(limit: 10);
        controller.loadStatistics();
        controller.loadEnhancedTrends(days: 14);
      }
    });
  }

  Future<void> _openCameraCheckin(BuildContext context) async {
    final result = await context.push<CameraMoodResult>('/mood-camera');
    if (result != null && context.mounted) {
      context.push('/mood-record', extra: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<MoodController>(context);
    final entries = controller.entries;
    final recentApi = controller.recentEntries;
    final loading = controller.loading;
    final stats = controller.statistics;

    final today =
        entries.where((e) => _isSameDay(e.date, DateTime.now())).toList();
    final latestTodayId = today.isNotEmpty ? today.last.id : null;

    // Show recent moods: prefer the dedicated recent endpoint (already sorted
    // newest-first), falling back to the full entries list. Exclude only the
    // specific entry shown in the Today card so the user sees meaningful
    // history even when they only have entries from today.
    final source = recentApi.isNotEmpty ? recentApi : entries;
    final recent = source
        .where((e) => e.id != latestTodayId)
        .take(3)
        .toList();

    return FeatureScaffold(
      title: 'Mood Tracking',
      body: loading
          ? const LoadingView()
          : controller.error != null
              ? EmptyStateView(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load moods',
                  message: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () {
                    final c = context.read<MoodController>();
                    c.loadEntries();
                    c.loadRecentEntries(limit: 10);
                    c.loadStatistics();
                    c.loadEnhancedTrends(days: 14);
                  },
                )
              : FeatureBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TodayCard(
                        today: today,
                        onRecord: () => context.push('/mood-record'),
                        onCamera: () => _openCameraCheckin(context),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _StatsRow(stats: stats),
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeader(
                        title: 'Recent moods',
                        actionLabel: 'See all',
                        onAction: () => context.push('/mood-history'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (recent.isEmpty && today.isEmpty)
                        EmptyStateView(
                          icon: Icons.mood_outlined,
                          title: 'No moods yet',
                          message:
                              'Record your first mood to start seeing your history.',
                          actionLabel: 'Record a mood',
                          onAction: () => context.push('/mood-record'),
                        )
                      else if (recent.isEmpty)
                        Text(
                          'You have logged a mood today. '
                          'Check back tomorrow to see your recent history.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                height: 1.5,
                              ),
                        )
                      else
                        ...recent.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: MoodEntryTile(
                              entry: e,
                              onTap: () => context.push('/mood-detail/${e.id}'),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      SectionHeader(
                        title: 'Trend preview',
                        actionLabel: 'View trends',
                        onAction: () => context.push('/mood-trends'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _TrendPreviewCard(
                        entries: entries,
                        enhancedTrends: controller.enhancedTrends,
                      ),
                    ],
                  ),
                ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Stats row with loading skeleton when data is not yet available.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      // Skeleton placeholder while stats load.
      return Row(
        children: List.generate(
          3,
          (_) => Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 48,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        MoodQuickStat(
          icon: Icons.local_fire_department_rounded,
          value: '${stats!['currentStreak'] ?? 0}',
          label: 'Day streak',
          color: Colors.orange,
        ),
        const SizedBox(width: AppSpacing.sm),
        MoodQuickStat(
          icon: Icons.date_range_rounded,
          value: '${stats!['entriesThisWeek'] ?? 0}',
          label: 'This week',
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.sm),
        MoodQuickStat(
          icon: Icons.speed_rounded,
          value: (stats!['averageIntensity'] ?? 0.0).toStringAsFixed(1),
          label: 'Avg intensity',
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.today,
    required this.onRecord,
    required this.onCamera,
  });

  final List<MoodEntry> today;
  final VoidCallback onRecord;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = today.isNotEmpty ? today.last : null;
    final mood = latest == null ? null : moodById(latest.moodId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Today's mood",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Log'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (latest == null || mood == null)
              Text(
                'No mood logged yet today. '
                'Tap Log to check in — it only takes a moment.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              )
            else
              Row(
                children: [
                  MoodDot(mood: mood, size: 54),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are feeling ${mood.label.toLowerCase()}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (latest.emotion != null) latest.emotion!,
                            '${latest.dayLabel} · ${latest.timeLabel}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (latest.intensity != null) ...[
                          const SizedBox(height: 6),
                          IntensityBar(
                            intensity: latest.intensity!,
                            height: 6,
                            showLabel: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendPreviewCard extends StatelessWidget {
  const _TrendPreviewCard({
    required this.entries,
    this.enhancedTrends,
  });

  final List<MoodEntry> entries;
  final Map<String, dynamic>? enhancedTrends;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last7 = _weekValues(entries, days: 7);
    final totalEntries = enhancedTrends?['totalEntries'] as int? ?? entries.length;
    final trendDirection = (enhancedTrends?['trend'] as Map<String, dynamic>?)?['direction'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Last 7 days',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (totalEntries > 0)
                  Text(
                    '$totalEntries total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (totalEntries == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'Start logging to see your mood trend here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              )
            else ...[
              TrendChart(
                data: last7,
                kind: TrendChartKind.bar,
                maxValue: 6,
                height: 140,
              ),
              if (trendDirection != null && trendDirection != 'unknown') ...[
                const SizedBox(height: AppSpacing.sm),
                _TrendSummary(direction: trendDirection),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static List<TrendDatum> _weekValues(List<MoodEntry> entries, {required int days}) {
    final now = DateTime.now();
    final result = <TrendDatum>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      final dayEntries = entries.where((e) =>
          e.date.year == day.year &&
          e.date.month == day.month &&
          e.date.day == day.day,
      ).toList();
      final avg = dayEntries.isEmpty
          ? 0.0
          : dayEntries
                  .map((e) => moodById(e.moodId).value.toDouble())
                  .reduce((a, b) => a + b) /
              dayEntries.length;
      result.add(TrendDatum(_shortWeekday(day.weekday), avg));
    }
    return result;
  }

  static String _shortWeekday(int weekday) => const [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
      ][weekday - 1];
}

/// Small trend direction badge shown below the chart.
class _TrendSummary extends StatelessWidget {
  const _TrendSummary({required this.direction});

  final String direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, color) = switch (direction) {
      'improving' => (
          Icons.trending_up_rounded,
          'Your mood is trending upward',
          Colors.green,
        ),
      'declining' => (
          Icons.trending_down_rounded,
          'Your mood has been trending down',
          theme.colorScheme.error,
        ),
      'fluctuating' => (
          Icons.show_chart_rounded,
          'Your mood has been varying',
          theme.colorScheme.tertiary,
        ),
      'stable' => (
          Icons.trending_flat_rounded,
          'Your mood has been stable',
          theme.colorScheme.primary,
        ),
      _ => (Icons.help_outline_rounded, '', theme.colorScheme.onSurfaceVariant),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
