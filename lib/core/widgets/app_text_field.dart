import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;
  final String? helperText;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: widget.obscureText ? _obscured : false,
        enabled: widget.enabled,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        maxLines: widget.maxLines,
        textCapitalization: widget.textCapitalization,
        inputFormatters: widget.inputFormatters,
        cursorColor: scheme.primary,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            color: hasError ? AppColors.danger : scheme.onSurfaceVariant,
          ),
          hintText: widget.hintText,
          prefixIcon: widget.prefixIcon != null
              ? Icon(
                  widget.prefixIcon,
                  size: 22,
                  color: hasError ? AppColors.danger : scheme.onSurfaceVariant,
                )
              : null,
          suffixIcon: widget.obscureText
              ? IconButton(
                  onPressed: () => setState(() => _obscured = !_obscured),
                  tooltip: _obscured ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : widget.suffixIcon,
          errorText: hasError ? widget.errorText : null,
          errorMaxLines: 2,
          errorStyle: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.danger,
            fontWeight: FontWeight.w500,
          ),
          helperText: widget.helperText,
          helperStyle: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          enabled: widget.enabled,
        ),
      ),
    );
  }
}
