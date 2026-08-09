import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/shared/widgets/app_logo.dart';

/// Calm hero visual for the Welcome screen.
class WellnessHero extends StatefulWidget {
  const WellnessHero({super.key, this.size = 240});

  final double size;

  @override
  State<WellnessHero> createState() => _WellnessHeroState();
}

class _WellnessHeroState extends State<WellnessHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    // Isolate the continuously animating hero so it never forces a repaint
    // of the rest of the screen (helps keep scrolling & navigation smooth).
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return SizedBox(
            width: s,
            height: s,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _halo(t, s, Colors.blue, 0),
                _halo(t, s, Colors.purple, 0.5),
                Container(
                  width: s * 0.82,
                  height: s * 0.82,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                ),
                const AppLogoMark(size: 150),
                Positioned(
                  top: s * 0.02,
                  right: s * 0.10,
                  child: _float(
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: s * 0.06,
                    ),
                    t,
                    0,
                  ),
                ),
                Positioned(
                  top: s * 0.24,
                  left: s * 0.04,
                  child: _float(
                    Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: s * 0.07,
                    ),
                    t,
                    0.25,
                  ),
                ),
                Positioned(
                  bottom: s * 0.16,
                  right: s * 0.05,
                  child: _float(
                    Icon(
                      Icons.spa_rounded,
                      color: Colors.white,
                      size: s * 0.06,
                    ),
                    t,
                    0.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _halo(double t, double size, Color color, double phase) {
    final progress = ((t + phase) % 1.0);
    final scale = 0.7 + 0.3 * progress;
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: 1 - progress,
        child: Container(
          width: size * 1.1,
          height: size * 1.1,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _float(Widget child, double t, double phase) {
    final dy = 6 * (0.5 - ((t + phase) % 1.0));
    return Transform.translate(
      offset: Offset(0, dy),
      child: child,
    );
  }
}
