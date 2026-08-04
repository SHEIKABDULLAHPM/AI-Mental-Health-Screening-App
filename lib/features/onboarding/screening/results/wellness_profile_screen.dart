import 'package:flutter/material.dart';

import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_section_card.dart';
import '../../../../core/widgets/smooth_page_route.dart';
import '../../dashboard/dashboard_screen.dart';
import '../../dashboard/widgets/score_ring.dart';
import '../screening_screen.dart';
import 'wellness_engine.dart';

class WellnessProfileScreen extends StatelessWidget {
  const WellnessProfileScreen({super.key, required this.report});

  final WellnessReport report;

  Color get _scoreColor =>
      AppColors.scoreColor(report.wellnessScore.toDouble());

  String get _scoreLabel {
    final score = report.wellnessScore;
    if (score >= 75) return 'Thriving';
    if (score >= 50) return 'Building';
    if (score >= 25) return 'Nurturing';
    return 'Prioritize care';
  }

  Future<void> _continue(BuildContext context) async {
    final auth = AuthService();
    await auth.completeOnboarding();
    await auth.saveWellness(
      score: report.wellnessScore,
      focus: report.focusLabel,
    );
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      SmoothPageRoute(builder: (_) => DashboardScreen(report: report)),
      (route) => false,
    );
  }

  void _retake(BuildContext context) {
    Navigator.of(
      context,
    ).pushReplacement(SmoothPageRoute(builder: (_) => const ScreeningScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF0D1413), Color(0xFF15211E)]
                : const [Color(0xFFF2FAF7), Color(0xFFE9F5F0)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.xl,
                    AppSpacing.page,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Your Results',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Center(
                        child: Text(
                          'Your Mental Wellness Profile',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: Text(
                          'Here is an AI-generated snapshot of your wellbeing based on your responses.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Center(
                        child: ScoreRing(
                          score: report.wellnessScore.toDouble(),
                          size: 190,
                          center: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${report.wellnessScore}',
                                style: theme.textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: _scoreColor,
                                ),
                              ),
                              Text(
                                'Wellness Score',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _scoreColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _scoreLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _scoreColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusPill(
                              icon: Icons.water_drop_outlined,
                              label: 'Stress Level',
                              value: report.stressLabel,
                              color: _stressColor(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _StatusPill(
                              icon: Icons.bedtime_outlined,
                              label: 'Sleep Quality',
                              value: report.sleepLabel,
                              color: _sleepColor(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.fitness_center_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    'Lifestyle Score',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${report.lifestyleScore}/100',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.scoreColor(
                                      report.lifestyleScore.toDouble(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: report.lifestyleScore / 100,
                                minHeight: 8,
                                backgroundColor: scheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                valueColor: AlwaysStoppedAnimation(
                                  AppColors.scoreColor(
                                    report.lifestyleScore.toDouble(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppSectionCard(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderColor: scheme.primary.withValues(alpha: 0.3),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.gradientStart,
                                    AppColors.gradientEnd,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.track_changes_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Primary Wellness Focus',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    report.focusLabel,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome_outlined,
                                  color: AppColors.gradientAccent,
                                  size: 22,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Text(
                                  'Your AI Insight',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              report.aiInsight,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.volunteer_activism_outlined,
                              color: AppColors.danger,
                              size: 22,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'If you are in crisis or having thoughts of harming yourself, please contact a trusted person, a local crisis helpline, or your nearest emergency service immediately.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w500,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.md,
                    AppSpacing.page,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: 'Continue to Dashboard',
                        icon: Icons.home_outlined,
                        onPressed: () => _continue(context),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Retake Assessment',
                        variant: AppButtonVariant.text,
                        onPressed: () => _retake(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _stressColor() {
    switch (report.stressLevel) {
      case StressLevel.low:
        return AppColors.success;
      case StressLevel.moderate:
        return AppColors.warning;
      case StressLevel.high:
        return AppColors.danger;
    }
  }

  Color _sleepColor() {
    switch (report.sleepQuality) {
      case SleepQuality.good:
        return AppColors.success;
      case SleepQuality.fair:
        return AppColors.warning;
      case SleepQuality.poor:
        return AppColors.danger;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
