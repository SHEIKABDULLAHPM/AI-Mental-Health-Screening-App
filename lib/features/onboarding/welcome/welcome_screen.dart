import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../login/login_screen.dart';
import '../register/register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const List<({IconData icon, String title, String subtitle})>
  _highlights = [
    (
      icon: Icons.psychology_alt_outlined,
      title: 'AI Screening',
      subtitle: 'Evidence-based PHQ-9, GAD-7 & more',
    ),
    (
      icon: Icons.auto_awesome_outlined,
      title: 'Smart Guidance',
      subtitle: 'Personalized AI wellness insights',
    ),
    (
      icon: Icons.monitor_heart_outlined,
      title: 'Daily Monitoring',
      subtitle: 'Track mood, sleep and stress',
    ),
    (
      icon: Icons.lock_outline_rounded,
      title: 'Private & Secure',
      subtitle: 'Your data stays protected',
    ),
  ];

  void _openLegal(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xxl,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'This is a summary for demonstration purposes. The full document is available in the app.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'MindEase helps you understand your mental wellbeing through structured screening. '
                'All responses are processed to generate guidance and are never sold to third parties. '
                'You can delete your data at any time. MindEase does not provide medical diagnosis or treatment.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).pushReplacement(SmoothPageRoute(builder: (_) => screen));
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
                    0,
                  ),
                  child: Column(
                    children: [
                      const WelcomeIllustration(),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        'Welcome to MindEase',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'A caring AI companion that helps you understand, track and improve your mental wellbeing — one gentle step at a time.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final itemWidth =
                              (constraints.maxWidth - AppSpacing.lg) / 2;
                          return Wrap(
                            spacing: AppSpacing.lg,
                            runSpacing: AppSpacing.lg,
                            children: _highlights
                                .map(
                                  (h) => _HighlightCard(
                                    width: itemWidth,
                                    highlight: h,
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              BottomActionBar(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      label: 'Get Started',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () => _go(context, const RegisterScreen()),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Sign In',
                      variant: AppButtonVariant.outline,
                      onPressed: () => _go(context, const LoginScreen()),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LegalLink(
                          label: 'Privacy Policy',
                          onTap: () => _openLegal(context, 'Privacy Policy'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '•',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _LegalLink(
                          label: 'Terms & Conditions',
                          onTap: () =>
                              _openLegal(context, 'Terms & Conditions'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.width, required this.highlight});

  final double width;
  final ({IconData icon, String title, String subtitle}) highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              highlight.icon,
              color: scheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            highlight.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            highlight.subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class WelcomeIllustration extends StatelessWidget {
  const WelcomeIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x59B7E7DA), Color(0x00B7E7DA)],
              ),
            ),
          ),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gradientEnd.withValues(
                alpha: isDark ? 0.16 : 0.12,
              ),
            ),
          ),
          AppLogo(
            size: 96,
            borderColor: isDark
                ? AppColors.backgroundDark
                : const Color(0xFFF2FAF7),
          ),
          const _FloatingChip(
            top: 18,
            left: 24,
            icon: Icons.mood_rounded,
            color: AppColors.gradientEnd,
            size: 46,
          ),
          const _FloatingChip(
            top: 40,
            right: 18,
            icon: Icons.favorite_rounded,
            color: AppColors.danger,
            size: 40,
          ),
          const _FloatingChip(
            bottom: 14,
            right: 44,
            icon: Icons.bedtime_rounded,
            color: AppColors.gradientAccent,
            size: 42,
          ),
          _FloatingChip(
            bottom: 26,
            left: 40,
            icon: Icons.self_improvement_rounded,
            color: scheme.primary,
            size: 38,
          ),
        ],
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({
    required this.icon,
    required this.color,
    this.size = 44,
    this.top,
    this.left,
    this.right,
    this.bottom,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? top;
  final double? left;
  final double? right;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.white,
            width: 1.5,
          ),
        ),
        child: Icon(icon, size: size * 0.5, color: color),
      ),
    );
  }
}
