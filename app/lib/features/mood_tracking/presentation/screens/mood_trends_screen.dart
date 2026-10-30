import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/widgets/mood_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';
import 'package:mindease/shared/widgets/trend_chart.dart';

enum _TrendRange { week, month }

/// Mood trends: weekly/monthly visualisation, distribution, intensity and patterns.
class MoodTrendsScreen extends StatefulWidget {
  const MoodTrendsScreen({super.key});

  @override
  State<MoodTrendsScreen> createState() => _MoodTrendsScreenState();
}

class _MoodTrendsScreenState extends State<MoodTrendsScreen> {
  _TrendRange _range = _TrendRange.week;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final controller = context.read<MoodController>();
        controller.loadEntries();
        controller.loadEnhancedTrends(days: 30);
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
    final trendsStatus = controller.enhancedTrends?['status'] as String?;
    final isInsufficientData = trendsStatus == 'INSUFFICIENT_DATA';
    final trendsMessage = controller.enhancedTrends?['message'] as String?;

    return FeatureScaffold(
      title: 'Mood Trends',
      body: loading
          ? const LoadingView()
          : controller.error != null && entries.isEmpty
              ? EmptyStateView(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load trends',
                  message: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () {
                    final c = context.read<MoodController>();
                    c.loadEntries();
                    c.loadEnhancedTrends(days: 30);
                    c.loadStatistics();
                  },
                )
              : FeatureBody(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stats != null) ...[
                      _StatsOverview(stats: stats),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    SegmentedButton<_TrendRange>(
                      segments: const [
                        ButtonSegment(
                          value: _TrendRange.week,
                          label: Text('Week'),
                          icon: Icon(Icons.calendar_view_week_rounded),
                        ),
                        ButtonSegment(
                          value: _TrendRange.month,
                          label: Text('Month'),
                          icon: Icon(Icons.calendar_view_month_rounded),
                        ),
                      ],
                      selected: {_range},
                      onSelectionChanged: (selection) =>
                          setState(() => _range = selection.first),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (isInsufficientData) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  trendsMessage ??
                                      'Not enough mood records to generate meaningful trends. '
                                      'Continue logging to see your patterns.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    SectionHeader(
                      title: _range == _TrendRange.week
                          ? 'Average mood · last 7 days'
                          : 'Average mood · last 4 weeks',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _MoodChartCard(
                      entries: entries,
                      range: _range,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Intensity trend'),
                    const SizedBox(height: AppSpacing.sm),
                    _IntensityTrendCard(entries: entries, range: _range),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Mood distribution'),
                    const SizedBox(height: AppSpacing.sm),
                    _DistributionCard(entries: entries),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Patterns'),
                    const SizedBox(height: AppSpacing.sm),
                    _PatternCard(entries: entries),
                    const SizedBox(height: AppSpacing.lg),
                    if (stats != null &&
                        stats['moodDistribution'] != null) ...[
                      const SectionHeader(title: 'Mood breakdown'),
                      const SizedBox(height: AppSpacing.sm),
                      _MoodBreakdownCard(
                        distribution:
                            Map<String, dynamic>.from(stats['moodDistribution']),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MoodQuickStat(
          icon: Icons.local_fire_department_rounded,
          value: '${stats['currentStreak'] ?? 0}',
          label: 'Current streak',
          color: Colors.orange,
        ),
        const SizedBox(width: AppSpacing.sm),
        MoodQuickStat(
          icon: Icons.emoji_events_rounded,
          value: '${stats['longestStreak'] ?? 0}',
          label: 'Best streak',
          color: Colors.amber,
        ),
        const SizedBox(width: AppSpacing.sm),
        MoodQuickStat(
          icon: Icons.speed_rounded,
          value: (stats['averageIntensity'] ?? 0.0).toStringAsFixed(1),
          label: 'Avg intensity',
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ],
    );
  }
}

class _MoodChartCard extends StatelessWidget {
  const _MoodChartCard({required this.entries, required this.range});

  final List<MoodEntry> entries;
  final _TrendRange range;

  @override
  Widget build(BuildContext context) {
    final data = range == _TrendRange.week
        ? _weekData(entries)
        : _monthData(entries);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TrendChart(
          data: data,
          kind: range == _TrendRange.week
              ? TrendChartKind.bar
              : TrendChartKind.line,
          maxValue: 6,
          height: 190,
        ),
      ),
    );
  }

  static List<TrendDatum> _weekData(List<MoodEntry> entries) {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day - (6 - i));
      return TrendDatum(
        _weekday(day.weekday),
        _avg(entries, day),
      );
    });
  }

  static List<TrendDatum> _monthData(List<MoodEntry> entries) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return List.generate(4, (i) {
      // Contiguous 7-day buckets ending today: W1 oldest … W4 current.
      // end is exclusive to avoid double-counting boundary midnights.
      final end = todayStart.add(Duration(days: -((3 - i) * 7) + 1));
      final start = end.subtract(const Duration(days: 7));
      final window = entries
          .where(
            (e) => !e.date.isBefore(start) && e.date.isBefore(end),
          )
          .toList();
      final avg = window.isEmpty
          ? 0.0
          : window
                  .map((e) => moodById(e.moodId).value.toDouble())
                  .reduce((a, b) => a + b) /
              window.length;
      return TrendDatum('W${i + 1}', avg);
    });
  }

  static double _avg(List<MoodEntry> entries, DateTime day) {
    final dayEntries = entries.where((e) =>
        e.date.year == day.year &&
        e.date.month == day.month &&
        e.date.day == day.day,).toList();
    if (dayEntries.isEmpty) return 0;
    return dayEntries
            .map((e) => moodById(e.moodId).value.toDouble())
            .reduce((a, b) => a + b) /
        dayEntries.length;
  }

  static String _weekday(int weekday) => const [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
      ][weekday - 1];
}

class _IntensityTrendCard extends StatelessWidget {
  const _IntensityTrendCard({required this.entries, required this.range});

  final List<MoodEntry> entries;
  final _TrendRange range;

  @override
  Widget build(BuildContext context) {
    final data = range == _TrendRange.week
        ? _weekIntensity(entries)
        : _monthIntensity(entries);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TrendChart(
          data: data,
          kind: TrendChartKind.line,
          maxValue: 10,
          height: 140,
        ),
      ),
    );
  }

  static List<TrendDatum> _weekIntensity(List<MoodEntry> entries) {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day - (6 - i));
      final dayEntries = entries
          .where((e) =>
              e.date.year == day.year &&
              e.date.month == day.month &&
              e.date.day == day.day &&
              e.intensity != null,)
          .toList();
      final avg = dayEntries.isEmpty
          ? 0.0
          : dayEntries.map((e) => e.intensity!.toDouble()).reduce((a, b) => a + b) /
              dayEntries.length;
      return TrendDatum(_weekday(day.weekday), avg);
    });
  }

  static List<TrendDatum> _monthIntensity(List<MoodEntry> entries) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return List.generate(4, (i) {
      final end = todayStart.add(Duration(days: -((3 - i) * 7) + 1));
      final start = end.subtract(const Duration(days: 7));
      final window = entries
          .where((e) =>
              !e.date.isBefore(start) &&
              e.date.isBefore(end) &&
              e.intensity != null,)
          .toList();
      final avg = window.isEmpty
          ? 0.0
          : window.map((e) => e.intensity!.toDouble()).reduce((a, b) => a + b) /
              window.length;
      return TrendDatum('W${i + 1}', avg);
    });
  }

  static String _weekday(int weekday) => const [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
      ][weekday - 1];
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.entries});

  final List<MoodEntry> entries;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final e in entries) {
      counts[e.moodId] = (counts[e.moodId] ?? 0) + 1;
    }
    final segments = kMoods
        .map((m) => (m.label, counts[m.id]?.toDouble() ?? 0, m.color))
        .where((s) => s.$2 > 0)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: segments.isEmpty
            ? Text(
                'Log moods to see how your feelings are spread.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            : DistributionBar(segments: segments),
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.entries});

  final List<MoodEntry> entries;

  @override
  Widget build(BuildContext context) {
    final positive =
        entries.where((e) => moodById(e.moodId).isPositive).length;
    final negative =
        entries.where((e) => moodById(e.moodId).isNegative).length;
    final neutral = entries.length - positive - negative;
    final total = entries.isEmpty ? 1 : entries.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _patternCell(
                    context,
                    Icons.trending_up_rounded,
                    AppColors.success,
                    '${(positive / total * 100).round()}%',
                    'Positive',
                  ),
                ),
                Expanded(
                  child: _patternCell(
                    context,
                    Icons.trending_flat_rounded,
                    AppColors.warning,
                    '${(neutral / total * 100).round()}%',
                    'Neutral',
                  ),
                ),
                Expanded(
                  child: _patternCell(
                    context,
                    Icons.trending_down_rounded,
                    AppColors.error,
                    '${(negative / total * 100).round()}%',
                    'Challenging',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'A positive-to-challenging ratio of ${positive + neutral} to '
              '$negative across your recent entries.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _patternCell(
    BuildContext context,
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _MoodBreakdownCard extends StatelessWidget {
  const _MoodBreakdownCard({required this.distribution});

  final Map<String, dynamic> distribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (distribution.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No distribution data yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final sorted = distribution.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    final maxCount = sorted.first.value as int;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: sorted.map((entry) {
            final mood = kMoods.where((m) => m.id == entry.key).firstOrNull;
            final count = entry.value as int;
            final fraction = maxCount > 0 ? count / maxCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  if (mood != null) ...[
                    Icon(mood.icon, size: 18, color: mood.color),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 60,
                      child: Text(
                        mood.label,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 82),
                  ],
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 12,
                        backgroundColor: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.08),
                        color: mood?.color ?? theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
