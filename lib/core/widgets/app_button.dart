import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum AppButtonVariant { primary, tonal, outline, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null && !loading;

    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      letterSpacing: 0.1,
    );

    Widget content;
    if (loading) {
      content = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color:
              variant == AppButtonVariant.primary ||
                  variant == AppButtonVariant.tonal
              ? scheme.onPrimary
              : destructive
              ? AppColors.danger
              : scheme.primary,
        ),
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(label, style: labelStyle, textAlign: TextAlign.center),
          ),
        ],
      );
    } else {
      content = Text(label, style: labelStyle, textAlign: TextAlign.center);
    }

    final minimumSize = fullWidth
        ? const Size.fromHeight(56)
        : const Size(64, 56);

    switch (variant) {
      case AppButtonVariant.primary:
        return FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            minimumSize: minimumSize,
            backgroundColor: destructive ? AppColors.danger : scheme.primary,
            foregroundColor: scheme.onPrimary,
            disabledBackgroundColor: scheme.primary.withValues(alpha: 0.35),
            disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: content,
        );
      case AppButtonVariant.tonal:
        return FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            minimumSize: minimumSize,
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            disabledBackgroundColor: scheme.secondaryContainer.withValues(
              alpha: 0.5,
            ),
            disabledForegroundColor: scheme.onSecondaryContainer.withValues(
              alpha: 0.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: content,
        );
      case AppButtonVariant.outline:
        return OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            minimumSize: minimumSize,
            foregroundColor: destructive ? AppColors.danger : scheme.primary,
            disabledForegroundColor: scheme.primary.withValues(alpha: 0.4),
            side: BorderSide(
              color: destructive ? AppColors.danger : scheme.primary,
              width: 1.3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: content,
        );
      case AppButtonVariant.text:
        return TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
            minimumSize: Size(
              minimumSize.width.isInfinite ? 0 : minimumSize.width,
              48,
            ),
            foregroundColor: destructive ? AppColors.danger : scheme.primary,
            disabledForegroundColor: scheme.primary.withValues(alpha: 0.4),
            textStyle: labelStyle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: content,
        );
    }
  }
}
