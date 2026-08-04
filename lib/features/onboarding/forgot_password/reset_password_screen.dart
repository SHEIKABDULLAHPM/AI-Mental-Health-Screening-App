import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_error_banner.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import 'reset_success_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _auth = AuthService();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _passwordError;
  String? _confirmError;
  String? _formError;
  bool _submitting = false;
  bool _touched = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _revalidate() {
    setState(() {
      _passwordError = Validators.password(_passwordController.text);
      _confirmError = Validators.confirmPassword(
        _confirmController.text,
        _passwordController.text,
      );
      _formError = null;
    });
  }

  Future<void> _submit() async {
    _touched = true;
    _revalidate();
    if (_passwordError != null || _confirmError != null) return;
    setState(() => _submitting = true);
    final ok = await _auth.updatePassword(
      email: widget.email,
      newPassword: _passwordController.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _formError = 'We could not update your password. Please try again.';
      });
      return;
    }
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(builder: (_) => const ResetSuccessScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strength = Validators.passwordStrength(_passwordController.text);
    final showStrength = _passwordController.text.isNotEmpty;

    return OnboardingPage(
      title: 'Create New Password',
      subtitle: 'Choose a strong password you have not used before.',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: AppButton(
        label: 'Update Password',
        icon: Icons.lock_reset_rounded,
        loading: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_formError != null) ...[
            FormErrorBanner(message: _formError!),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppTextField(
            controller: _passwordController,
            label: 'New Password',
            hintText: 'Minimum 8 characters',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _touched ? _passwordError : null,
            enabled: !_submitting,
            onChanged: (_) {
              if (_touched) _revalidate();
            },
          ),
          if (showStrength) ...[
            const SizedBox(height: AppSpacing.sm),
            _StrengthChips(strength: strength),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppTextField(
            controller: _confirmController,
            label: 'Confirm New Password',
            hintText: 'Re-enter your new password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _touched ? _confirmError : null,
            enabled: !_submitting,
            onChanged: (_) {
              if (_touched) _revalidate();
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}

class _StrengthChips extends StatelessWidget {
  const _StrengthChips({required this.strength});

  final ({bool length, bool uppercase, bool number, bool symbol}) strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <({String label, bool ok})>[
      (label: '8+ characters', ok: strength.length),
      (label: 'Uppercase', ok: strength.uppercase),
      (label: 'Number', ok: strength.number),
      (label: 'Symbol', ok: strength.symbol),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: items.map((item) {
        final color = item.ok
            ? AppColors.success
            : theme.colorScheme.onSurfaceVariant;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: item.ok
                ? AppColors.success.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.ok ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
