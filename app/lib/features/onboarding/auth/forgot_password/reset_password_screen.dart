import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/core/utils/validators.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/shared/widgets/form_error_banner.dart';

/// Step 3 — create a new password with a live strength indicator.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final Map<String, String> _fieldErrors = {};
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  int _strength() {
    var s = 0;
    final p = _password.text;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  Color _strengthColor() {
    switch (_strength()) {
      case 0:
      case 1:
        return AppColors.error;
      case 2:
        return AppColors.warning;
      case 3:
        return AppColors.info;
      default:
        return AppColors.success;
    }
  }

  String _strengthLabel() {
    switch (_strength()) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  Future<void> _submit() async {
    final errors = <String, String>{
      if (Validators.password(_password.text) != null)
        'password': Validators.password(_password.text)!,
      if (Validators.confirmPassword(_confirm.text, _password.text) != null)
        'confirm': Validators.confirmPassword(_confirm.text, _password.text)!,
    };
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    context.go('/forgot-password/success');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = _strength();
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: AppBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Create a new password',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Choose something unique you haven\u2019t used before.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_formError != null) ...[
                      FormErrorBanner(message: _formError!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppTextField(
                      controller: _password,
                      label: 'New Password',
                      hint: '8+ characters with a number & capital letter',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      errorText: _fieldErrors['password'],
                      onChanged: (_) => setState(() {
                        _fieldErrors.remove('password');
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Strength',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (_password.text.isNotEmpty)
                                Text(
                                  _strengthLabel(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: _strengthColor(),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: strength / 4,
                              minHeight: 6,
                              color: _strengthColor(),
                              backgroundColor: theme
                                  .colorScheme.primaryContainer
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _confirm,
                      label: 'Confirm New Password',
                      hint: 'Repeat your new password',
                      prefixIcon: Icons.lock_clock_outlined,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      errorText: _fieldErrors['confirm'],
                      onChanged: (_) => setState(() {
                        _fieldErrors.remove('confirm');
                      }),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Update Password',
                      loading: _busy,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
