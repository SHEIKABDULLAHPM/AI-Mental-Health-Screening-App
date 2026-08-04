import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_loading_dots.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../dashboard/dashboard_screen.dart';
import '../welcome/welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.auth});

  final AuthService? auth;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AuthService _auth = widget.auth ?? AuthService();
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  static const List<String> _tasks = [
    'Checking authentication',
    'Initializing app',
    'Loading preferences',
  ];

  String _task = _tasks.first;
  int _taskIndex = 0;
  Timer? _taskTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scaleIn = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    _startTasks();
    _decideNavigation();
  }

  void _startTasks() {
    _taskTimer = Timer.periodic(const Duration(milliseconds: 950), (_) {
      if (!mounted) return;
      setState(() {
        _taskIndex = (_taskIndex + 1) % _tasks.length;
        _task = _tasks[_taskIndex];
      });
    });
  }

  Future<void> _decideNavigation() async {
    await Future.delayed(const Duration(milliseconds: 3400));
    if (!mounted || _navigated) return;
    _navigated = true;
    _taskTimer?.cancel();
    final onboarded = await _auth.isOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(
        builder: (_) =>
            onboarded ? const DashboardScreen() : const WelcomeScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _taskTimer?.cancel();
    _controller.dispose();
    super.dispose();
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
        child: Stack(
          children: [
            Positioned(
              top: -90,
              right: -70,
              child: _blob(
                AppColors.gradientStart.withValues(alpha: isDark ? 0.2 : 0.14),
                250,
              ),
            ),
            Positioned(
              top: 130,
              left: -90,
              child: _blob(
                AppColors.gradientAccent.withValues(alpha: isDark ? 0.14 : 0.1),
                210,
              ),
            ),
            Positioned(
              bottom: -110,
              left: 30,
              child: _blob(
                AppColors.gradientEnd.withValues(alpha: isDark ? 0.16 : 0.12),
                270,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _fadeIn,
                    child: ScaleTransition(
                      scale: _scaleIn,
                      child: AppLogo(
                        size: 108,
                        borderColor: isDark
                            ? AppColors.backgroundDark
                            : const Color(0xFFF2FAF7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Text(
                      'MindEase',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Text(
                      'Your companion for mental wellbeing',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: Column(
                children: [
                  AppLoadingDots(color: scheme.primary),
                  const SizedBox(height: AppSpacing.lg),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _task,
                      key: ValueKey(_task),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Text(
                'Version 1.0.0',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
