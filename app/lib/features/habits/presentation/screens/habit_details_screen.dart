import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/habits/presentation/state/habit_controller.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';
import 'package:mindease/shared/widgets/trend_chart.dart';

/// Habit details: stats, weekly trend, recent streak history.
class HabitDetailsScreen extends StatefulWidget {
  const HabitDetailsScreen({super.key, required this.habitId});

  final String habitId;

  @override
  State<HabitDetailsScreen> createState() => _HabitDetailsScreenState();
}

const List<String> _kDayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayShort(int index) => _kDayLabels[index % _kDayLabels.length];

class _HabitDetailsScreenState extends State<HabitDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HabitController>(context, listen: false)
          .loadHabitDetails(widget.habitId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Provider.of<HabitController>(context);
    final habit = controller.currentHabit;
    final color = habit?.color ?? theme.colorScheme.primary;

    return FeatureScaffold(
      title: 'Habit',
      body: controller.loading || habit == null
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
                      radius: 30,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(habit.icon, color: color, size: 30),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habit.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Goal: ${habit.goalLabel}',
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
                Row(
                  children: [
                    _StatCard(
                      label: 'Streak',
                      value: '${habit.streak}',
                      icon: Icons.local_fire_department_rounded,
                      color: color,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StatCard(
                      label: 'This week',
                      value: '${habit.completedThisWeek}/7',
                      icon: Icons.check_circle_rounded,
                      color: color,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StatCard(
                      label: 'Best streak',
                      value: '${habit.streak > 7 ? habit.streak : 7}',
                      icon: Icons.trending_up_rounded,
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last 7 days',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          height: 120,
                          child: TrendChart(
                            kind: TrendChartKind.bar,
                            maxValue: 1,
                            lineColor: color,
                            data: [
                              for (var i = 0; i < habit.week.length; i++)
                                TrendDatum(
                                  _dayShort(i),
                                  habit.week[i] ? 1.0 : 0.0,
                                  color: habit.week[i] ? color : null,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          habit.completedThisWeek >= 5
                              ? 'Strong week — keep the momentum going!'
                              : 'A few more days and your streak grows.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upcoming goal',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Keep a ${habit.streak + 1}-day streak to beat '
                          'your personal best.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        LinearProgressIndicator(
                          value: habit.weekRate,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: AppSpacing.sm),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
