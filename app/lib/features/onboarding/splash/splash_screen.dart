import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_loading_dots.dart';
import 'package:mindease/shared/widgets/app_logo.dart';

/// Launch screen: animates the brand while checking local state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scaleIn = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _decideNavigation();
  }

  Future<void> _decideNavigation() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted || _navigated) return;
    _navigated = true;
    final prefs = await AppPreferences.load();
    if (!mounted) return;
    context.go(prefs.isOnboarded ? '/dashboard' : '/welcome');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Responsive: the brand group is always vertically centered and stays
    // within bounds on short screens (falls back to a fixed scroll so it can
    // never overflow), and all text is width-constrained so nothing wraps
    // off-screen on narrow devices or large text scales.
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 540;
              final logoSize = compact
                  ? 96.0
                  : (constraints.maxHeight >= 700 ? 148.0 : 120.0);
              final gap = compact ? 18.0 : 30.0;
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            FadeTransition(
                              opacity: _fadeIn,
                              child: ScaleTransition(
                                scale: _scaleIn,
                                child: AppLogo(
                                  size: logoSize,
                                  showTagline: true,
                                ),
                              ),
                            ),
                            SizedBox(height: gap),
                            RepaintBoundary(
                              child: FadeTransition(
                                opacity: _fadeIn,
                                child: const AppLoadingDots(size: 12),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Preparing your experience…',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Version 1.0.0',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
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
}
