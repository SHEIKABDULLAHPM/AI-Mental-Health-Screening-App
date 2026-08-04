import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.borderColor});

  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gradientStart.withValues(alpha: 0.35),
                  blurRadius: size * 0.4,
                  offset: Offset(0, size * 0.12),
                ),
              ],
            ),
            child: Icon(
              Icons.self_improvement_rounded,
              color: Colors.white,
              size: size * 0.52,
            ),
          ),
          Positioned(
            right: -size * 0.06,
            bottom: -size * 0.03,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                color: AppColors.gradientAccent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor ?? Theme.of(context).colorScheme.surface,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gradientAccent.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: size * 0.17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
