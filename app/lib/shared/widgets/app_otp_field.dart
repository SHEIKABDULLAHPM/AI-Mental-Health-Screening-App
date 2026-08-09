import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';

/// 6-digit OTP input with auto-advance and paste support.
class AppOtpField extends StatefulWidget {
  const AppOtpField({
    super.key,
    required this.length,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.error,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final String? error;

  @override
  State<AppOtpField> createState() => _AppOtpFieldState();
}

class _AppOtpFieldState extends State<AppOtpField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _handlePaste(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final fill =
        digits.padRight(widget.length, '0').substring(0, widget.length);
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = fill[i];
    }
    _focusNodes.last.requestFocus();
    widget.onChanged?.call(_value);
    widget.onCompleted(_value);
  }

  void _onDigitChange(int index, String value) {
    if (value.length > 1) {
      _handlePaste(value);
      return;
    }
    _controllers[index].text = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(widget.length, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index < widget.length - 1 ? AppSpacing.sm : 0,
                ),
                child: SizedBox(
                  height: 60,
                  child: _digitField(index),
                ),
              ),
            );
          }),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _digitField(int index) {
    final theme = Theme.of(context);
    final focused = _focusNodes[index].hasFocus;
    return TextField(
      controller: _controllers[index],
      focusNode: _focusNodes[index],
      enabled: widget.enabled,
      maxLength: 2,
      autofocus: index == 0,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      onChanged: (v) => _onDigitChange(index, v),
      decoration: InputDecoration(
        counterText: '',
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: focused
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: focused ? 2 : 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
      ),
    );
  }
}
