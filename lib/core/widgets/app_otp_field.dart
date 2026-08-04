import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

class AppOtpField extends StatefulWidget {
  const AppOtpField({
    super.key,
    this.length = 6,
    required this.onChanged,
    this.onCompleted,
    this.error = false,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCompleted;
  final bool error;

  @override
  State<AppOtpField> createState() => _AppOtpFieldState();
}

class _AppOtpFieldState extends State<AppOtpField> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode();
  String _value = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onText(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > widget.length) {
      _controller.text = digits.substring(0, widget.length);
      _controller.selection = TextSelection.collapsed(offset: widget.length);
    }
    setState(() => _value = _controller.text);
    widget.onChanged(_value);
    if (_value.length == widget.length) {
      widget.onCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: SizedBox(
        height: 64,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  showCursor: true,
                  onChanged: _onText,
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(widget.length, (index) {
                  final isActive =
                      index == _value.length && _focusNode.hasFocus;
                  final hasChar = index < _value.length;
                  return _OtpBox(
                    char: hasChar ? _value[index] : '',
                    active: isActive,
                    error: widget.error,
                    filled: hasChar,
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.char,
    required this.active,
    required this.error,
    required this.filled,
  });

  final String char;
  final bool active;
  final bool error;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color borderColor;
    if (error) {
      borderColor = AppColors.danger;
    } else if (active) {
      borderColor = scheme.primary;
    } else if (filled) {
      borderColor = scheme.primary.withValues(alpha: 0.35);
    } else {
      borderColor = scheme.outlineVariant.withValues(alpha: 0.7);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 52,
      height: 64,
      decoration: BoxDecoration(
        color: filled
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: active || error ? 2 : 1.3,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        char.isEmpty ? '' : char,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
