import 'package:flutter/material.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_section_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/coming_soon_screen.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../screening/results/wellness_engine.dart';
import 'widgets/score_ring.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.auth, this.report});

  final AuthService? auth;
  final WellnessReport? report;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final AuthService _auth;
  int _tab = 0;
  UserProfile? _user;
  WellnessReport? _report;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? AuthService();
    _report = widget.report;
    _load();
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    if (_report == null) {
      final saved = await _auth.loadWellness();
      if (saved != null && mounted) {
        setState(() {
          _report = WellnessReport(
            wellnessScore: saved['score'] as int? ?? 0,
            stressLevel: StressLevel.moderate,
            lifestyleScore: 0,
            sleepQuality: SleepQuality.fair,
            focus: _focusFromLabel(saved['focus'] as String?),
            aiInsight:
                'Welcome back. Keep up your gentle routine today and take a moment to check in with yourself.',
            phqTotal: 0,
            gadTotal: 0,
            pssTotal: 0,
            whoPercent: 0,
          );
        });
      }
    }
    if (mounted) setState(() => _user = user);
  }

  WellnessFocus _focusFromLabel(String? label) {
    switch (label) {
      case 'Stress Management':
        return WellnessFocus.stressManagement;
      case 'Sleep & Rest':
        return WellnessFocus.sleep;
      case 'Mood Support':
        return WellnessFocus.moodSupport;
      case 'Positive Wellbeing':
        return WellnessFocus.wellbeing;
      default:
        return WellnessFocus.balance;
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openFeature(String title, IconData icon) {
    Navigator.of(context).push(
      SmoothPageRoute(
        builder: (_) => ComingSoonScreen(title: title, icon: icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _tab == 0
            ? KeyedSubtree(
                key: const ValueKey('dashboard-home'),
                child: _buildHome(context),
              )
            : KeyedSubtree(
                key: ValueKey('tab-$_tab'),
                child: _buildTabPlaceholder(context),
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        height: 68,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Check-in',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
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

  Widget _buildTabPlaceholder(BuildContext context) {
    const titles = ['Check-in', 'AI Coach', 'Progress', 'Profile'];
    const icons = [
      Icons.favorite_outline_rounded,
      Icons.forum_outlined,
      Icons.insights_outlined,
      Icons.person_outline_rounded,
    ];
    final title = titles[_tab - 1];
    return ComingSoonScreen(
      title: title,
      icon: icons[_tab - 1],
      subtitle:
          'The $title experience is being crafted for you. Check back soon!',
    );
  }

  Widget _buildHome(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final firstName = _user?.firstName ?? 'there';
    final initials = _user?.initials ?? '?';
    final score = _report?.wellnessScore ?? 76;
    final insight =
        _report?.aiInsight ??
        'Take a moment for yourself today. A short check-in can help you understand how you are feeling.';

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, firstName, initials),
            const SizedBox(height: AppSpacing.xl),
            AppSectionCard(
              child: Row(
                children: [
                  ScoreRing(
                    score: score.toDouble(),
                    size: 120,
                    strokeWidth: 11,
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$score',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.scoreColor(score.toDouble()),
                          ),
                        ),
                        Text(
                          'Wellness',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Wellness Score',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Based on your latest screening. Keep showing up for yourself - small steps count.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gradientStart.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        "Today's AI Insight",
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    insight,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.95),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Quick Access',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - AppSpacing.lg) / 2;
                return Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.lg,
                  children: [
                    _QuickAccessCard(
                      width: itemWidth,
                      icon: Icons.favorite_rounded,
                      title: 'Daily Check-in',
                      subtitle: '2 min',
                      color: AppColors.danger,
                      onTap: () => _openFeature(
                        'Daily Check-in',
                        Icons.favorite_rounded,
                      ),
                    ),
                    _QuickAccessCard(
                      width: itemWidth,
                      icon: Icons.mood_rounded,
                      title: 'Mood Tracking',
                      subtitle: 'Track moods',
                      color: AppColors.warning,
                      onTap: () =>
                          _openFeature('Mood Tracking', Icons.mood_rounded),
                    ),
                    _QuickAccessCard(
                      width: itemWidth,
                      icon: Icons.edit_note_rounded,
                      title: 'Journal',
                      subtitle: 'Write freely',
                      color: AppColors.info,
                      onTap: () =>
                          _openFeature('Journal', Icons.edit_note_rounded),
                    ),
                    _QuickAccessCard(
                      width: itemWidth,
                      icon: Icons.forum_rounded,
                      title: 'AI Coach',
                      subtitle: 'Chat with AI',
                      color: AppColors.gradientAccent,
                      onTap: () =>
                          _openFeature('AI Coach', Icons.forum_rounded),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String firstName, String initials) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$firstName 👋',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () =>
                  AppSnackbar.show(context, 'You are all caught up!'),
              icon: const Icon(Icons.notifications_none_rounded, size: 26),
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerLow,
                minimumSize: const Size(46, 46),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
            ),
            shape: BoxShape.circle,
          ),
          child: Text(
            initials,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
