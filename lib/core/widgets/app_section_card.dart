import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.borderRadius = 20,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.colorScheme.surfaceContainerLow;

    final decoration = BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: borderColor != null ? Border.all(color: borderColor!) : null,
      boxShadow: shadow
          ? [
              const BoxShadow(
                color: AppColors.shadow,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ]
          : null,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap != null) {
      return Padding(
        padding: margin,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Ink(
            decoration: decoration,
            child: InkWell(
              borderRadius: BorderRadius.circular(borderRadius),
              onTap: onTap,
              child: content,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: margin,
      child: DecoratedBox(decoration: decoration, child: content),
    );
  }
}
