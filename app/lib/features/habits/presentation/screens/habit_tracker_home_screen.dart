import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/habits/presentation/state/habit_controller.dart';
import 'package:mindease/features/habits/presentation/widgets/habit_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Habit Tracker home: weekly overview + today's habits.
class HabitTrackerHomeScreen extends StatefulWidget {
  const HabitTrackerHomeScreen({super.key});

  @override
  State<HabitTrackerHomeScreen> createState() => _HabitTrackerHomeScreenState();
}

class _HabitTrackerHomeScreenState extends State<HabitTrackerHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HabitController>(context, listen: false).loadHabits();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Provider.of<HabitController>(context);
    final habits = controller.habits;
    final doneCount = habits.where((h) => h.doneToday).length;
    final totalStreak =
        habits.fold<int>(0, (sum, h) => sum + h.streak);

    return FeatureScaffold(
      title: 'Habit Tracker',
      actions: [
        IconButton(
          tooltip: 'Add habit',
          onPressed: () => context.push('/habits/add'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      body: controller.loading && habits.isEmpty
          ? const LoadingView()
          : habits.isEmpty
              ? const EmptyStateView(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'No habits yet',
                  message: 'Add a habit to start building a routine.',
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
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$doneCount of ${habits.length} done today',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Total streak: $totalStreak days',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: CircularProgressIndicator(
                                    value: habits.isEmpty
                                        ? 0
                                        : doneCount / habits.length,
                                    strokeWidth: 6,
                                    backgroundColor: theme.colorScheme
                                        .primary
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                Text(
                                  '${habits.isEmpty ? 0 : (doneCount / habits.length * 100).round()}%',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeader(
                      title: 'Today',
                      actionLabel: '${habits.length} habits',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...habits.map(
                      (h) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: HabitCard(
                          habit: h,
                          onToggle: () => controller.toggleHabit(h.id),
                          onTap: () => context.push('/habits/${h.id}'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
