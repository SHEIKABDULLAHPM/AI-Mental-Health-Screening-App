import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/ring_painter.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';
import 'package:mindease/features/onboarding/screening/wellness_engine.dart';

/// AI-generated initial wellness summary presented after screening.
class WellnessProfileScreen extends StatefulWidget {
  const WellnessProfileScreen({super.key});

  @override
  State<WellnessProfileScreen> createState() => _WellnessProfileScreenState();
}

class _WellnessProfileScreenState extends State<WellnessProfileScreen> {
  bool _busy = false;

  WellnessReport get _report => ScreeningSession.report!;

  Future<void> _continue() async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    final prefs = await AppPreferences.load();
    await prefs.setOnboarded(true);
    if (!mounted) return;
    context.go('/dashboard');
  }

  void _retake() {
    ScreeningSession.controller.jumpToStep(0);
    context.go('/screening');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          'Your Initial\nWellness Profile',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Center(child: _ScoreRing(report.wellnessScore)),
                      const SizedBox(height: AppSpacing.lg),
                      _MetricGrid(report: report),
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        icon: Icons.auto_awesome_rounded,
                        iconColor: theme.colorScheme.tertiary,
                        title: 'Primary Wellness Focus',
                        subtitle: report.focusLabel,
                        children: [
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Your AI-generated insight',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            report.aiInsight,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppButton(
                        label: 'Continue',
                        icon: Icons.arrow_forward_rounded,
                        loading: _busy,
                        onPressed: _continue,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Retake Assessment',
                        variant: AppButtonVariant.text,
                        onPressed: _busy ? null : _retake,
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
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing(this.score);

  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppColors.scoreColor(score.toDouble());
    return Column(
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: CustomPaint(
            painter: RingPainter(
              value: score.toDouble(),
              color: color,
              trackColor: color.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$score',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    'Wellness Score',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          switch (score) {
            >= 75 => 'You’re doing great — keep it up!',
            >= 50 => 'A balanced starting point — let’s build on it.',
            _ => 'You’re taking a brave first step — we’ve got your back.',
          },
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.report});

  final WellnessReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.self_improvement_rounded,
                label: 'Stress Level',
                value: report.stressLabel,
                color: switch (report.stressLevel) {
                  StressLevel.low => AppColors.success,
                  StressLevel.moderate => AppColors.warning,
                  StressLevel.high => AppColors.error,
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Metric(
                icon: Icons.bolt_rounded,
                label: 'Lifestyle Score',
                value: report.lifestyleScore.toString(),
                color: AppColors.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.bedtime_rounded,
                label: 'Sleep Quality',
                value: report.sleepLabel,
                color: switch (report.sleepQuality) {
                  SleepQuality.good => AppColors.success,
                  SleepQuality.fair => AppColors.warning,
                  SleepQuality.poor => AppColors.error,
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Metric(
                icon: Icons.psychology_alt_rounded,
                label: 'Focus',
                value: _shortFocus(report.focusLabel),
                color: AppColors.tertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _shortFocus(String label) => switch (label) {
        'Stress Management' => 'Stress',
        'Positive Wellbeing' => 'Wellbeing',
        _ => label,
      };
}

class _Metric extends StatelessWidget {
  const _Metric({
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
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: AppSpacing.sm),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ignore_for_file: unused_element
