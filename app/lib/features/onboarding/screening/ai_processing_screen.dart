import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_loading_dots.dart';
import 'package:mindease/shared/widgets/app_logo.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';
import 'package:mindease/features/onboarding/screening/wellness_engine.dart';

/// Shows AI analysing responses before presenting the wellness profile.
class AiProcessingScreen extends StatefulWidget {
  const AiProcessingScreen({super.key});

  @override
  State<AiProcessingScreen> createState() => _AiProcessingScreenState();
}

class _AiProcessingScreenState extends State<AiProcessingScreen>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Analyzing your responses…',
    'Recognizing patterns…',
    'Creating your wellness profile…',
    'Preparing personalized insights…',
  ];

  late final AnimationController _pulse;

  Timer? _messageTimer;
  int _messageIndex = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _messageTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
      });
    });

    _computeLater();
  }

  Future<void> _computeLater() async {
    await Future.delayed(const Duration(milliseconds: 4200));
    if (!mounted || _completed) return;
    _completed = true;
    _messageTimer?.cancel();
    ScreeningSession.report =
        WellnessEngine.compute(ScreeningSession.controller);
    if (!mounted) return;
    context.go('/wellness-profile');
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                RepaintBoundary(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.25),
                                    AppColors.primary.withValues(alpha: 0.02),
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: AppColors.gradientStart,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 50,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: AppLogoMark(size: 88),
                              ),
                            ),
                            for (final phase in [0.0, 0.33, 0.66])
                              Builder(
                                builder: (context) {
                                  final progress =
                                      (_pulse.value + phase) % 1.0;
                                  return Transform.scale(
                                    scale: 1 + 0.6 * progress,
                                    child: Opacity(
                                      opacity: (1 - progress).clamp(0.0, 1.0),
                                      child: Container(
                                        width: 170,
                                        height: 170,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: Text(
                    _messages[_messageIndex],
                    key: ValueKey(_messageIndex),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Center(child: AppLoadingDots(size: 14)),
                const SizedBox(height: AppSpacing.xl),
                SafeArea(
                  top: false,
                  child: Center(
                    child: Text(
                      'Please keep the app open — this usually takes a few seconds.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
