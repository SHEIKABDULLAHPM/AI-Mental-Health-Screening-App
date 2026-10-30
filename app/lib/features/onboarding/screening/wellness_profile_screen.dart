import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_result.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/physical_wellness/presentation/state/lifestyle_wellness_controller.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/safety_support_card.dart';
import 'package:mindease/shared/widgets/ring_painter.dart';
import 'package:mindease/shared/widgets/wellness_analysis_result_card.dart';
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



  Future<void> _analyzeMentalWellness() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await wellnessAnalysisApi.analyzeMentalWellness();
      if (!mounted) return;
      await showWellnessAnalysisSheet(
        context,
        WellnessAnalysisResult.mental(result),
      );
      if (mounted) {
        try {
          context.read<RecommendationController>().loadRecommendations();
          context.read<LifestyleWellnessController>().refreshAll();
        } catch (_) {}
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not run the mental wellness analysis. Check your connection and try again.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _analyzeMentalWellness,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      else if (_profile == null || !_profile!.hasScores)
                        // Nothing to show until the deterministic scores land.
                        // The LLM insight arriving later never gates them.
                        _PendingCard()
                      else ...[
                        if (_profile!.safetyFlag) ...[
                          const SafetySupportCard(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        Center(
                          child: _ScoreRing(_profile!.wellnessScore ?? 0),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _MoodProgressCard(profile: _profile!),
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
                              _profile!.hasInsight
                                  ? _profile!.aiInsight!
                                  : 'Your personalised insight is still being '
                                      'written. Everything above is already '
                                      'final and will not change.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.6,
                                fontStyle: _profile!.hasInsight
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _WellnessAnalysisActions(
                          onAnalyzeMental: _analyzeMentalWellness,
                          loading: _busy,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _NextStepCard(profile: _profile!),
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
                        onPressed:
                            _loading || _error != null ? null : _continue,
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

/// Integrated Mood Check-In summary for the final assessment.
/// Shows the authoritative backend mood state; degrades to an honest
/// "unavailable" state for older profiles instead of inventing values.
class _MoodProgressCard extends StatelessWidget {
  const _MoodProgressCard({required this.profile});

  final MindeaseProfile profile;


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!profile.hasMood) {
      return AppSectionCard(
        icon: Icons.mood_outlined,
        iconColor: theme.colorScheme.tertiary,
        title: 'Mood Progress',
        subtitle: 'No onboarding mood recorded',
        children: [
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Log a mood check-in to start tracking your mood pattern over time.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Log a Check-In',
            icon: Icons.mood_rounded,
            onPressed: () => context.push('/mood-record'),
          ),
        ],
      );
    }
    final mood = moodById(profile.moodMood!);
    final trend = profile.moodTrendDirection ?? 'unknown';
    final (trendLabel, trendIcon, trendColor) = switch (trend) {
      'improving' => (
          'Improving',
          Icons.trending_up_rounded,
          AppColors.success
        ),
      'declining' => (
          'Needs attention',
          Icons.trending_down_rounded,
          AppColors.error
        ),
      'stable' => (
          'Stable',
          Icons.remove_rounded,
          theme.colorScheme.onSurfaceVariant
        ),
      'fluctuating' => ('Varying', Icons.swap_vert_rounded, AppColors.warning),
      _ => (
          'Unknown',
          Icons.help_outline_rounded,
          theme.colorScheme.onSurfaceVariant
        ),
    };
    final cameraLine = cameraSignalLine(
      profile.cameraEmotion,
      profile.signalAgreement,
      ferDisplayName,
    );
    return AppSectionCard(
      icon: Icons.mood_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: 'Mood Progress',
      subtitle: profile.moodTrendDescription?.isNotEmpty == true
          ? profile.moodTrendDescription
          : null,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: mood.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(mood.icon, color: mood.color, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mood.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (profile.moodEmotion?.isNotEmpty == true)
                    Text(
                      profile.moodEmotion!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: trendColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(trendIcon, size: 14, color: trendColor),
                  const SizedBox(width: 4),
                  Text(
                    trendLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: trendColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if ((profile.moodHistoryCount ?? 0) > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Based on ${profile.moodHistoryCount} recent check-in${profile.moodHistoryCount == 1 ? '' : 's'} alongside this assessment.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (cameraLine != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            cameraLine,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/mood-trends'),
            icon: const Icon(Icons.show_chart_rounded, size: 18),
            label: const Text('View mood trends'),
          ),
        ),
      ],
    );
  }
}

/// Deterministic next-step recommendation derived from real assessment data
/// (trend + focus). No AI call — the personalized narrative lives in the
/// insight card above.
class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.profile});

  final MindeaseProfile profile;

  (String, String, IconData, String) _nextStep() {
    if (profile.moodTrendDirection == 'declining') {
      return (
        'Keep a gentle daily check-in',
        'Your recent pattern dips a little. A short daily check-in helps you notice what lifts your mood.',
        Icons.mood_rounded,
        '/mood-record',
      );
    }
    return switch (profile.primaryFocus) {
      'SLEEP' => (
          'Wind down for better rest',
          'A consistent bedtime is your highest-impact step. Try a short relaxation exercise tonight.',
          Icons.bedtime_rounded,
          '/relax',
        ),
      'STRESS_MANAGEMENT' => (
          'Take a two-minute breather',
          'When things feel heavy, a short breathing exercise can help you reset.',
          Icons.self_improvement_rounded,
          '/relax',
        ),
      'MOOD_SUPPORT' => (
          'Keep your check-in streak going',
          'Small daily wins add up. Log your mood tomorrow to keep the picture clear.',
          Icons.mood_rounded,
          '/mood-record',
        ),
      _ => (
          'Explore your recommendations',
          'Your profile is ready — see what\u2019s picked for you this week.',
          Icons.lightbulb_outline_rounded,
          '/recommendations',
        ),
    };
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, body, icon, route) = _nextStep();
    return AppSectionCard(
      icon: Icons.rocket_launch_rounded,
      iconColor: theme.colorScheme.primary,
      title: 'Recommended next step',
      subtitle: title,
      children: [
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Continue',
          icon: icon,
          onPressed: () => context.push(route),
        ),
      ],
    );
  }
}

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
    final sessionMood = ScreeningSession.controller.mood;
    final hasLocalMood = sessionMood.isComplete;
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
        if (hasLocalMood) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                moodById(sessionMood.currentMoodId!).icon,
                color: moodById(sessionMood.currentMoodId!).color,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Mood recorded: ${moodById(sessionMood.currentMoodId!).label}'
                  '${sessionMood.emotion?.isNotEmpty == true ? ' · ${sessionMood.emotion}' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
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



class _WellnessAnalysisActions extends StatelessWidget {
  const _WellnessAnalysisActions({required this.onAnalyzeMental, this.loading = false});

  final VoidCallback onAnalyzeMental;
  final bool loading;


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      icon: Icons.psychology_outlined,
      iconColor: theme.colorScheme.primary,
      title: 'Mental Wellness',
      subtitle: 'Analyze your mental wellbeing',
      children: [
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Get a real-time mental wellness analysis using your latest assessment and mood data.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: loading ? null : onAnalyzeMental,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(loading ? 'Analyzing…' : 'Analyze Mental Wellness'),
          ),
        ),
        if (loading) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Analyzing your latest screening and mood data — this can take a few seconds.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
