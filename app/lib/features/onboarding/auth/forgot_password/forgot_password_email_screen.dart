import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/core/utils/validators.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/shared/widgets/form_error_banner.dart';

/// Step 1 — enter the registered email to receive a reset OTP.
class ForgotPasswordEmailScreen extends StatefulWidget {
  const ForgotPasswordEmailScreen({super.key});

  @override
  State<ForgotPasswordEmailScreen> createState() =>
      _ForgotPasswordEmailScreenState();
}

class _ForgotPasswordEmailScreenState extends State<ForgotPasswordEmailScreen> {
  final _email = TextEditingController();
  String? _error;
  String? _emailError;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _continuePressed() async {
    final e = Validators.email(_email.text);
    setState(() => _emailError = e);
    if (e != null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The backend returns the same success response for unknown emails so
      // accounts cannot be enumerated. Any failure here is transport/server.
      await mindeaseApi.forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() => _busy = false);
      context.go(
        '/forgot-password/otp?email=${Uri.encodeComponent(_email.text.trim())}',
      );
    } on Failure catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Unable to send the code right now. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                        Icons.mark_email_read_outlined,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Forgot your password?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      "No worries. Enter your email and we'll send you a "
                      'secure 6-digit code to reset it.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_error != null) ...[
                      FormErrorBanner(message: _error!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppTextField(
                      controller: _email,
                      label: 'Email Address',
                      hint: 'you@example.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      errorText: _emailError,
                      onChanged: (_) => setState(() => _emailError = null),
                      onSubmitted: (_) => _continuePressed(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Send Code',
                      loading: _busy,
                      onPressed: _continuePressed,
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
