import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/ring_painter.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';

/// AI-generated initial wellness summary presented after screening. The
/// report is fetched from the backend (GET /wellness-profile) — never invented
/// on the client.
class WellnessProfileScreen extends StatefulWidget {
  const WellnessProfileScreen({super.key});

  @override
  State<WellnessProfileScreen> createState() => _WellnessProfileScreenState();
}

class _WellnessProfileScreenState extends State<WellnessProfileScreen> {
  bool _busy = false;
  bool _loading = true;
  String? _error;
  MindeaseProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await mindeaseApi.wellnessProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load your wellness profile right now. '
            'Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    context.go('/dashboard');
  }

  void _retake() {
    ScreeningSession.retake();
    context.go('/screening');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppSpacing.xl),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_error != null)
                        _ErrorCard(message: _error!, onRetry: _load)
                      else if (_profile == null || _profile!.isPending)
                        _PendingCard()
                      else ...[
                        Center(
                          child: _ScoreRing(_profile!.wellnessScore ?? 0),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _MetricGrid(profile: _profile!),
                        const SizedBox(height: AppSpacing.lg),
                        AppSectionCard(
                          icon: Icons.auto_awesome_rounded,
                          iconColor: theme.colorScheme.tertiary,
                          title: 'Primary Wellness Focus',
                          subtitle: _focusLabel(_profile!.primaryFocus),
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
                              _profile!.aiInsight ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ],
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
                        onPressed: _loading || _error != null ? null : _continue,
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

String _focusLabel(String? focus) => switch (focus) {
      'STRESS_MANAGEMENT' => 'Stress Management',
      'SLEEP' => 'Sleep & Rest',
      'MOOD_SUPPORT' => 'Mood Support',
      'WELLBEING' => 'Positive Wellbeing',
      _ => 'Maintain Balance',
    };

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      icon: Icons.cloud_off_rounded,
      iconColor: AppColors.error,
      title: 'Profile unavailable',
      children: [
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Try Again',
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      icon: Icons.hourglass_top_rounded,
      iconColor: AppColors.tertiary,
      title: 'Profile in progress',
      children: [
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your assessment has been submitted and stored securely. Your '
          'personal wellness profile and insights are being prepared and will '
          'appear here once the secure analysis is complete.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
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
  const _MetricGrid({required this.profile});

  final MindeaseProfile profile;

  @override
  Widget build(BuildContext context) {
    final stressLevel = profile.stressLevel ?? 'LOW';
    final sleepQuality = profile.sleepQuality ?? 'FAIR';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: Icons.self_improvement_rounded,
                label: 'Stress Level',
                value: _stressLabel(stressLevel),
                color: switch (stressLevel) {
                  'HIGH' => AppColors.error,
                  'MODERATE' => AppColors.warning,
                  _ => AppColors.success,
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Metric(
                icon: Icons.bolt_rounded,
                label: 'Lifestyle Score',
                value: (profile.lifestyleScore ?? 0).toString(),
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
                value: _sleepLabel(sleepQuality),
                color: switch (sleepQuality) {
                  'GOOD' => AppColors.success,
                  'POOR' => AppColors.error,
                  _ => AppColors.warning,
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Metric(
                icon: Icons.psychology_alt_rounded,
                label: 'Focus',
                value: _shortFocus(_focusLabel(profile.primaryFocus)),
                color: AppColors.tertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _stressLabel(String value) => switch (value) {
        'HIGH' => 'High',
        'MODERATE' => 'Moderate',
        _ => 'Low',
      };

  String _sleepLabel(String value) => switch (value) {
        'GOOD' => 'Good',
        'POOR' => 'Poor',
        _ => 'Fair',
      };

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
