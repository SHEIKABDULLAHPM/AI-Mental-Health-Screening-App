import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_indeterminate_bar.dart';
import '../../../../core/widgets/smooth_page_route.dart';
import '../results/wellness_engine.dart';
import '../results/wellness_profile_screen.dart';
import '../screening_controller.dart';

class AiProcessingScreen extends StatefulWidget {
  const AiProcessingScreen({super.key, required this.controller});

  final ScreeningController controller;

  @override
  State<AiProcessingScreen> createState() => _AiProcessingScreenState();
}

class _AiProcessingScreenState extends State<AiProcessingScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _messages = [
    'Analyzing your responses',
    'Creating your wellness profile',
    'Preparing personalized insights',
    'Building your care plan',
  ];

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  Timer? _messageTimer;
  int _messageIndex = 0;
  String _message = _messages.first;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _messageTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
        _message = _messages[_messageIndex];
      });
    });
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 5600));
    if (!mounted || _navigated) return;
    _navigated = true;
    _messageTimer?.cancel();
    _pulse.stop();
    final report = WellnessEngine.compute(widget.controller);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(builder: (_) => WellnessProfileScreen(report: report)),
    );
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
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Column(
              children: [
                const Spacer(flex: 2),
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          size: const Size(240, 240),
                          painter: _PulseRingsPainter(
                            progress: _pulse.value,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gradientStart.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.psychology_alt_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SizedBox(width: 220, child: AppIndeterminateBar(height: 10)),
                const SizedBox(height: AppSpacing.xl),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    _message,
                    key: ValueKey(_message),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This usually takes a few seconds',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  _PulseRingsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width * 0.46;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxRadius * (0.25 + t * 0.75);
      final alpha = (1 - t) * 0.55;
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
