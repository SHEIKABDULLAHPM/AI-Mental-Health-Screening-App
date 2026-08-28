import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/api/journey.dart';
import 'package:mindease/core/di/app_services.dart';
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
    String destination = '/welcome';
    final token = await sessionStore.accessToken();
    if (token != null) {
      try {
        final user = await mindeaseApi.me();
        destination = await JourneyRouter.nextRoute(user);
      } on Object {
        // The stored session is invalid/expired - treat as signed out.
        await sessionStore.clear();
        destination = '/welcome';
      }
    }
    if (!mounted) return;
    context.go(destination);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Responsive layout:
    //  - The brand lockup (vector artwork, 1342x894) is sized to the largest
    //    width that still leaves a clean reserved block for the loading dots,
    //    status line and version at the bottom, and the height is capped the
    //    same way so it never overflows on short screens.
    //  - The loading dots, status line and version live in a clean block that
    //    is always anchored to the bottom edge.
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 560;
              const bottomBlockHeight = 150.0;
              final availableHeight = (constraints.maxHeight - bottomBlockHeight)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
              // Lockup aspect ratio (w:h = 1342:894).
              const aspect = 894 / 1342;
              final byWidth = constraints.maxWidth * (compact ? 0.46 : 0.7);
              final byHeight = availableHeight / aspect;
              final logoSize = (byWidth < byHeight ? byWidth : byHeight)
                  .clamp(140.0, 480.0);
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: FadeTransition(
                          opacity: _fadeIn,
                          child: ScaleTransition(
                            scale: _scaleIn,
                            child: AppLogo(
                              size: logoSize,
                              showTagline: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                        child: FadeTransition(
                          opacity: _fadeIn,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const RepaintBoundary(
                                child: AppLoadingDots(size: 12),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Preparing your experience…',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 10),
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
