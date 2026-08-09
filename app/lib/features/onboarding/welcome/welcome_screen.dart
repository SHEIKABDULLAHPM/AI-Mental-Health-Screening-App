import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/wellness_hero.dart';

/// Introduction screen shown to new & returning users.
typedef _Feature = ({IconData icon, String title, String description});

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const List<_Feature> _features = [
    (
      icon: Icons.psychology_alt_rounded,
      title: 'AI Mental Health Screening',
      description:
          'Answer clinically validated questionnaires and get instant insights.',
    ),
    (
      icon: Icons.tips_and_updates_rounded,
      title: 'Personalized Wellness Guidance',
      description: 'Receive tailored guidance shaped around your responses.',
    ),
    (
      icon: Icons.monitor_heart_rounded,
      title: 'Daily Wellness Monitoring',
      description: 'Track check-ins, mood, habits and progress over time.',
    ),
    (
      icon: Icons.lock_rounded,
      title: 'Secure & Private',
      description: 'Your data is encrypted, stored securely and never shared.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          // Responsive: the column stretches to fill the viewport when it
          // fits and falls back to scrolling on shorter screens, so the
          // content never overflows (SafeArea + scrolling keeps every
          // control reachable on small devices, text-scale & landscape).
          child: LayoutBuilder(
            builder: (context, constraints) {
              final heroSize = constraints.maxHeight < 620
                  ? 120.0
                  : (constraints.maxHeight >= 900 ? 160.0 : 125.0);
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          Center(child: WellnessHero(size: heroSize)),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'MindEase',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Your companion for understanding, nurturing and '
                            'growing your mental wellbeing — one small step at a time.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ..._features.map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _FeatureTile(f),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppButton(
                            label: 'Get Started',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: () => context.go('/register'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppButton(
                            label: 'Sign In',
                            variant: AppButtonVariant.outlined,
                            onPressed: () => context.go('/login'),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              AppTextLink(
                                text: 'Privacy Policy',
                                onPressed: () => _showDoc(
                                    context,
                                    'Privacy Policy',
                                    'We collect only the information needed '
                                        'to provide personalized wellness '
                                        'guidance.\n\nYour screening responses '
                                        'are used solely to generate your '
                                        'wellness profile and '
                                        'recommendations.\n\nYou can request '
                                        'deletion of your data at any time.'),
                              ),
                              const Text(
                                ' • ',
                                style: TextStyle(fontSize: 12),
                              ),
                              AppTextLink(
                                text: 'Terms & Conditions',
                                onPressed: () => _showDoc(
                                    context,
                                    'Terms & Conditions',
                                    'MindEase provides guidance and wellness '
                                        'insights. It is not a medical '
                                        'diagnosis or a substitute for '
                                        'professional care.\n\nIf you are in '
                                        'crisis, contact a local emergency '
                                        'service or a mental health '
                                        'professional immediately.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showDoc(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl,),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.feature);

  final ({IconData icon, String title, String description}) feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(feature.icon, size: 19, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                feature.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
