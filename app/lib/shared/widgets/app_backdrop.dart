import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_colors.dart';

/// Decorative soft gradient blobs behind full-bleed onboarding screens.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, this.child, this.intensity = 1.0});

  final Widget? child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.gradientStart.withValues(alpha: 0.16 * intensity);
    final secondary =
        AppColors.gradientAccent.withValues(alpha: 0.12 * intensity);
    final accent = AppColors.accent.withValues(alpha: 0.10 * intensity);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF10142A), const Color(0xFF0E1220)]
              : [const Color(0xFFF2F5FF), const Color(0xFFF5F7FD)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -120, right: -80, child: _blob(primary, 280)),
          Positioned(top: 160, left: -110, child: _blob(secondary, 240)),
          Positioned(bottom: -140, right: -60, child: _blob(accent, 260)),
          if (child != null) child!,
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}
