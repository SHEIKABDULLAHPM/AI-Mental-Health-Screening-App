import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/ai_coach/presentation/screens/ai_coach_home_screen.dart';
import 'package:mindease/features/habits/presentation/state/habit_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/shared/widgets/ai_insight_card.dart';
import 'package:mindease/shared/widgets/app_logout_tile.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/feature_grid_tile.dart';
import 'package:mindease/shared/widgets/ring_painter.dart';
import 'package:mindease/features/dashboard/presentation/state/progress_controller.dart';

/// Landing page after onboarding — the feature hub entry point.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tabIndex = 0;
  String _name = 'there';
  int? _score;
  String _insight = '';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MoodController>(context, listen: false).loadEntries();
      Provider.of<HabitController>(context, listen: false).loadHabits();
    });
  }

  Future<void> _loadDashboard() async {
    try {
      final dash = await mindeaseApi.dashboard();
      if (!mounted) return;
      setState(() {
        _name = dash.name;
        _score = dash.wellnessScore;
        _insight = dash.todayInsight ?? '';
      });
    } on Object {
      // Keep the default greeting; the name/score come from the backend.
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _insightText => _insight.isEmpty
      ? 'Complete your screening to unlock your personal wellness insight.'
      : _insight;

  void _openTab(int index) {
    if (index == 0) {
      setState(() => _tabIndex = 0);
      return;
    }
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _HomeTab(
            name: _name,
            greeting: _greeting,
            score: _score,
            insight: _insightText,
          ),
          const _CheckInTab(),
          const AiCoachHomeScreen(),
          const _ProgressTab(),
          _ProfileTab(name: _name),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _openTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Check-in',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy_rounded),
            label: 'AI Coach',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.name,
    required this.greeting,
    required this.score,
    required this.insight,
  });

  final String name;
  final String greeting;
  final int? score;
  final String insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(name: name, greeting: greeting),
            const SizedBox(height: AppSpacing.lg),
            _WellnessScoreCard(score: score),
            const SizedBox(height: AppSpacing.md),
            AIInsightCard(
              title: "Today's AI Insight",
              text: insight,
              icon: Icons.auto_awesome_rounded,
              iconColor: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Quick access',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.0,
              children: [
                FeatureGridTile(
                  icon: Icons.mood_outlined,
                  label: 'Mood Tracking',
                  subtitle: 'How you feel',
                  color: theme.colorScheme.tertiary,
                  onTap: () => context.push('/mood'),
                ),
                FeatureGridTile(
                  icon: Icons.menu_book_outlined,
                  label: 'Journal',
                  subtitle: 'Daily entries',
                  color: theme.colorScheme.secondary,
                  onTap: () => context.push('/journal'),
                ),
                FeatureGridTile(
                  icon: Icons.smart_toy_outlined,
                  label: 'AI Coach',
                  subtitle: 'Chat support',
                  color: AppColors.primary,
                  onTap: () => context.push('/ai-coach'),
                ),
                FeatureGridTile(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'Recommendations',
                  subtitle: 'For you',
                  color: AppColors.warning,
                  onTap: () => context.push('/recommendations'),
                ),
                FeatureGridTile(
                  icon: Icons.emoji_events_outlined,
                  label: 'Challenges',
                  subtitle: 'Build streaks',
                  color: AppColors.success,
                  onTap: () => context.push('/challenges'),
                ),
                FeatureGridTile(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Habit Tracker',
                  subtitle: 'Daily routines',
                  color: AppColors.tertiary,
                  onTap: () => context.push('/habits'),
                ),
                FeatureGridTile(
                  icon: Icons.self_improvement_rounded,
                  label: 'Relax & Heal',
                  subtitle: 'Breathe & calm',
                  color: const Color(0xFF7C6BF0),
                  onTap: () => context.push('/relax'),
                ),
                FeatureGridTile(
                  icon: Icons.mail_outline_rounded,
                  label: 'Future Letters',
                  subtitle: 'Letters to you',
                  color: const Color(0xFF37A2E8),
                  onTap: () => context.push('/letters'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.greeting});

  final String name;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.isEmpty ? 'U' : name[0].toUpperCase();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        _Avatar(initial: initial),
        const SizedBox(width: AppSpacing.sm),
        _NotificationButton(),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filledTonal(
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined, size: 22),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 22,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initial,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          tooltip: 'Notifications',
          onPressed: () {},
          icon: const Icon(Icons.notifications_outlined, size: 22),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _WellnessScoreCard extends StatelessWidget {
  const _WellnessScoreCard({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = score ?? 0;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wellness Score',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  score == null ? '—' : '$value',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  score == null
                      ? 'Complete the screening to see your score.'
                      : 'Your overall wellbeing snapshot.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 86,
            height: 86,
            child: CustomPaint(
              painter: RingPainter(
                value: value.toDouble(),
                color: Colors.white,
                trackColor: Colors.white.withValues(alpha: 0.25),
              ),
              child: Center(
                child: Text(
                  score == null ? '?' : '$value',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = name == 'there' ? 'Your account' : name;
    final initial = name == 'there' ? 'U' : name[0].toUpperCase();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        initial,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Signed in to your Synora account',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Settings',
                      onPressed: () => context.push('/settings'),
                      icon: const Icon(Icons.settings_outlined, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  icon: Icons.security_rounded,
                  iconColor: theme.colorScheme.secondary,
                  title: 'Account',
                  subtitle:
                      'Manage your sign-in and control access to your data.',
                  children: const [
                    SizedBox(height: AppSpacing.xs),
                    AppLogoutTile(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Daily Check-in tab: quick mood record + short screening entry.
class _CheckInTab extends StatelessWidget {
  const _CheckInTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check-in',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A minute for yourself.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              icon: Icons.mood_rounded,
              iconColor: theme.colorScheme.tertiary,
              title: 'How are you feeling?',
              subtitle: 'Record your current mood',
              children: [
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final mood in kMoods)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          onTap: () => context.push('/mood-record'),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            child: Column(
                              children: [
                                Icon(
                                  mood.icon,
                                  color: mood.color,
                                  size: 26,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mood.label,
                                  style: theme.textTheme.labelSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/mood-record'),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Add details'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppSectionCard(
              icon: Icons.fact_check_rounded,
              iconColor: theme.colorScheme.secondary,
              title: 'Quick screening',
              subtitle: 'Reassess your mental wellbeing',
              children: [
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'A short questionnaire that refreshes your wellness insight '
                  'and recommendations.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/screening'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start screening'),
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

/// Progress tab: real-time aggregated progress from all features via ProgressController.
class _ProgressTab extends StatefulWidget {
  const _ProgressTab();

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = Provider.of<ProgressController>(context, listen: false);
      if (ctrl.progress == null && !ctrl.loading) {
        ctrl.loadProgress();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = Provider.of<ProgressController>(context);
    final habitCtrl = Provider.of<HabitController>(context);
    final habits = habitCtrl.habits;
    final doneToday = habits.where((h) => h.doneToday).length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                if (ctrl.loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => ctrl.refresh(),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Error state ──
            if (ctrl.error != null) ...[
              _ErrorBanner(message: ctrl.error!),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── Wellness Score ──
            _WellnessScoreSection(ctrl: ctrl),
            const SizedBox(height: AppSpacing.md),

            // ── Mood Progress ──
            _MoodProgressSection(ctrl: ctrl),
            const SizedBox(height: AppSpacing.md),

            // ── Journal Progress ──
            _JournalProgressSection(ctrl: ctrl),
            const SizedBox(height: AppSpacing.md),

            // ── Activities ──
            _ActivitiesSection(ctrl: ctrl),
            const SizedBox(height: AppSpacing.md),

            // ── Habits (local) ──
            AppSectionCard(
              icon: Icons.check_circle_outline_rounded,
              iconColor: theme.colorScheme.secondary,
              title: 'Habits today',
              children: [
                const SizedBox(height: AppSpacing.sm),
                if (habits.isEmpty)
                  Text(
                    'No habits yet. Add some to track your daily routines.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  for (final habit in habits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Icon(habit.icon, color: habit.color, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              habit.title,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '${habit.completedThisWeek}/7',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    '$doneToday of ${habits.length} done today.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Engagement ──
            _EngagementSection(ctrl: ctrl),
            const SizedBox(height: AppSpacing.md),

            // ── Insights ──
            _InsightsSection(ctrl: ctrl),
          ],
        ),
      ),
    );
  }
}

/// Shows wellness score ring with trend label.
class _WellnessScoreSection extends StatelessWidget {
  const _WellnessScoreSection({required this.ctrl});
  final ProgressController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = ctrl.wellnessScore;
    final value = score ?? 0;

    return AppSectionCard(
      icon: Icons.favorite_rounded,
      iconColor: AppColors.tertiary,
      title: 'Wellness score',
      subtitle: ctrl.wellnessScoreLabel,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: SizedBox(
            width: 130,
            height: 130,
            child: CustomPaint(
              painter: RingPainter(
                value: (value / 100).clamp(0.0, 1.0),
                color: theme.colorScheme.primary,
                trackColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score == null ? '—' : '$value',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (score != null)
                      Text(
                        'out of 100',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (score == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Complete a screening to unlock your wellness score.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (ctrl.wellnessTrend != 'stable' && score != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: _TrendChip(
              trend: ctrl.wellnessTrend,
            ),
          ),
        ],
      ],
    );
  }
}

/// Mood progress section with trend, streak, and distribution.
class _MoodProgressSection extends StatelessWidget {
  const _MoodProgressSection({required this.ctrl});
  final ProgressController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = ctrl.moodHasData;

    return AppSectionCard(
      icon: Icons.show_chart_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: 'Mood progress',
      subtitle: ctrl.moodTrendDescription.isNotEmpty
          ? ctrl.moodTrendDescription
          : null,
      trailing: hasData
          ? TextButton(
              onPressed: () => context.push('/mood-trends'),
              child: const Text('Trends'),
            )
          : null,
      children: [
        if (!hasData)
          Text(
            'Record your mood to see progress here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          // Stats row
          Row(
            children: [
              _StatTile(
                label: 'This week',
                value: '${ctrl.moodEntriesThisWeek}',
                icon: Icons.calendar_today_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                label: 'Streak',
                value: '${ctrl.moodCurrentStreak}d',
                icon: Icons.local_fire_department_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                label: 'Total',
                value: '${ctrl.moodTotalEntries}',
                icon: Icons.mood_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Trend chip
          Row(
            children: [
              _TrendChip(trend: ctrl.moodTrend),
              if (ctrl.moodDominant != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _InfoChip(
                  label: 'Dominant: ${ctrl.moodDominant}',
                  color: theme.colorScheme.tertiaryContainer,
                ),
              ],
            ],
          ),
          // Distribution
          if (ctrl.moodDistribution.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'All-time mood distribution',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...ctrl.moodDistribution.entries.map((e) {
              final total = ctrl.moodTotalEntries;
              final pct = total > 0 ? (e.value / total) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        e.key,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.toDouble(),
                          minHeight: 8,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${e.value}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}

/// Journal progress section.
class _JournalProgressSection extends StatelessWidget {
  const _JournalProgressSection({required this.ctrl});
  final ProgressController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = ctrl.journalHasData;

    return AppSectionCard(
      icon: Icons.menu_book_rounded,
      iconColor: theme.colorScheme.secondary,
      title: 'Journal activity',
      subtitle: hasData
          ? '${ctrl.journalEntriesThisWeek} entries this week'
          : 'Write entries to track your thoughts',
      children: [
        if (!hasData)
          Text(
            'Start journaling to see your activity here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Row(
            children: [
              _StatTile(
                label: 'This week',
                value: '${ctrl.journalEntriesThisWeek}',
                icon: Icons.edit_note_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                label: 'Total',
                value: '${ctrl.journalTotalEntries}',
                icon: Icons.menu_book_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                label: 'Level',
                value: _activityLabel(ctrl.journalActivityLevel),
                icon: Icons.speed_rounded,
              ),
            ],
          ),
          if (ctrl.journalRecentEmotions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Recent emotions',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final e in ctrl.journalRecentEmotions)
                  _InfoChip(
                    label: e,
                    color: theme.colorScheme.secondaryContainer,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// Activity progress from recommendation interactions.
class _ActivitiesSection extends StatelessWidget {
  const _ActivitiesSection({required this.ctrl});
  final ProgressController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = ctrl.activitiesHasData;

    return AppSectionCard(
      icon: Icons.fitness_center_rounded,
      iconColor: AppColors.warning,
      title: 'Completed activities',
      subtitle: hasData
          ? '${ctrl.activitiesTotalCompleted} total completed'
          : 'Complete recommended activities to see progress',
      trailing: hasData
          ? TextButton(
              onPressed: () => context.push('/recommendations'),
              child: const Text('Browse'),
            )
          : null,
      children: [
        if (!hasData)
          Text(
            'Start an activity to track your progress here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Row(
            children: [
              _StatTile(
                label: 'This week',
                value: '${ctrl.activitiesCompletedThisWeek}',
                icon: Icons.check_circle_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                label: 'Total done',
                value: '${ctrl.activitiesTotalCompleted}',
                icon: Icons.emoji_events_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                label: 'Helpful',
                value: '${ctrl.activitiesHelpfulCount}',
                icon: Icons.thumb_up_rounded,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Cross-feature engagement section.
class _EngagementSection extends StatelessWidget {
  const _EngagementSection({required this.ctrl});
  final ProgressController ctrl;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      icon: Icons.workspace_premium_rounded,
      iconColor: AppColors.success,
      title: 'Engagement',
      subtitle: ctrl.engagementSummary,
      children: [
        Row(
          children: [
            _StatTile(
              label: 'Features',
              value: '${ctrl.engagementFeaturesUsed}',
              icon: Icons.apps_rounded,
            ),
            const SizedBox(width: AppSpacing.md),
            _StatTile(
              label: 'Active week',
              value: '${ctrl.engagementActiveFeatures}',
              icon: Icons.trending_up_rounded,
            ),
            const SizedBox(width: AppSpacing.md),
            _StatTile(
              label: 'Coach chats',
              value: '${ctrl.engagementCoachConversations}',
              icon: Icons.chat_rounded,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _ConsistencyBadge(level: ctrl.engagementConsistencyLevel),
      ],
    );
  }
}

/// Personalized insights section.
class _InsightsSection extends StatelessWidget {
  const _InsightsSection({required this.ctrl});
  final ProgressController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insights = ctrl.insights;

    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Insights',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...insights.map((insight) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _InsightTile(insight: insight),
            ),),
      ],
    );
  }
}

// ── Reusable sub-widgets ──

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.trend});
  final String trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, color) = switch (trend) {
      'improving' => ('Improving', Icons.trending_up_rounded, AppColors.success),
      'declining' => ('Needs attention', Icons.trending_down_rounded, AppColors.error),
      'stable' => ('Stable', Icons.remove_rounded, theme.colorScheme.onSurfaceVariant),
      'fluctuating' => ('Varying', Icons.swap_vert_rounded, AppColors.warning),
      _ => ('Unknown', Icons.help_outline_rounded, theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _ConsistencyBadge extends StatelessWidget {
  const _ConsistencyBadge({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, color) = switch (level) {
      'high' => ('High consistency', Icons.emoji_events_rounded, AppColors.success),
      'moderate' => ('Moderate consistency', Icons.trending_up_rounded, AppColors.warning),
      'low' => ('Getting started', Icons.hourglass_top_rounded, theme.colorScheme.primary),
      _ => ('Inactive', Icons.hourglass_empty_rounded, theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight});
  final Map<String, dynamic> insight;

  IconData _iconFromString(String iconName) {
    return switch (iconName) {
      'local_fire_department' => Icons.local_fire_department_rounded,
      'trending_up' => Icons.trending_up_rounded,
      'trending_down' => Icons.trending_down_rounded,
      'edit_note' => Icons.edit_note_rounded,
      'check_circle' => Icons.check_circle_rounded,
      'emoji_events' => Icons.emoji_events_rounded,
      _ => Icons.lightbulb_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = insight['type'] as String? ?? '';
    final title = insight['title'] as String? ?? '';
    final description = insight['description'] as String? ?? '';
    final icon = insight['icon'] as String? ?? 'lightbulb';

    final accentColor = switch (type) {
      'streak' => AppColors.warning,
      'trend' => AppColors.success,
      'journal' => theme.colorScheme.secondary,
      'activity' => AppColors.primary,
      'engagement' => AppColors.tertiary,
      _ => theme.colorScheme.primary,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFromString(icon), size: 18, color: accentColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _activityLabel(String level) {
  return switch (level) {
    'very_active' => 'Very active',
    'active' => 'Active',
    'moderate' => 'Moderate',
    'occasional' => 'Occasional',
    _ => 'Inactive',
  };
}

