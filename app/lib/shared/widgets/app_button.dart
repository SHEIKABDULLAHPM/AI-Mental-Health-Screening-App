import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';

/// Reusable primary / outlined / text buttons with loading support.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  /// Primary action (filled) or secondary outlined action.
  final AppButtonVariant variant;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (loading) {
      content = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
        ],
      );
    }

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: loading ? null : onPressed,
          child: content,
        ),
      AppButtonVariant.outlined => OutlinedButton(
          onPressed: loading ? null : onPressed,
          child: content,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: loading ? null : onPressed,
          child: content,
        ),
      AppButtonVariant.danger => FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            disabledBackgroundColor:
                Theme.of(context).colorScheme.error.withValues(alpha: 0.35),
            disabledForegroundColor:
                Theme.of(context).colorScheme.onError.withValues(alpha: 0.7),
          ),
          child: content,
        ),
    };

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

enum AppButtonVariant { primary, outlined, text, danger }

/// Promotes text-only content to a tappable TextButton-like row for footers,
/// e.g. "Already have an account? Sign In".
class AppTextLink extends StatelessWidget {
  const AppTextLink({
    super.key,
    required this.text,
    required this.onPressed,
    this.prefix,
    this.style,
  });

  final String text;
  final String? prefix;
  final VoidCallback onPressed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = style ??
        theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    return Center(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text.rich(
            TextSpan(
              text: (prefix == null) ? '' : '$prefix ',
              style: effectiveStyle,
              children: [
                TextSpan(
                  text: text,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
