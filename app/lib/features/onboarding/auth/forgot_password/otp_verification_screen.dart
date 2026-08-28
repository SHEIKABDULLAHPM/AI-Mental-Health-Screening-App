import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_otp_field.dart';
import 'package:mindease/shared/widgets/form_error_banner.dart';

/// Step 2 — verify the 6-digit code sent to the user's email.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  String _code = '';
  String? _error;
  bool _busy = false;

  Timer? _timer;
  Duration _remaining = const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _email =>
      GoRouterState.of(context).uri.queryParameters['email'] ?? '';

  void _startTimer() {
    _timer?.cancel();
    setState(() => _remaining = const Duration(seconds: 30));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 1) {
        t.cancel();
        setState(() => _remaining = Duration.zero);
      } else {
        setState(() => _remaining -= const Duration(seconds: 1));
      }
    });
  }

  void _resend() {
    final email = _email;
    setState(() => _error = null);
    _startTimer();
    if (email.isEmpty) {
      setState(() => _error = 'Email missing. Please start again.');
      return;
    }
    // Fire-and-forget: issues a fresh OTP for the same email.
    mindeaseApi.forgotPassword(email).catchError((_) {
      if (!mounted) return;
      setState(() => _error = 'Could not resend the code. Please try again.');
    });
  }

  Future<void> _verify() async {
    if (_busy) return;
    final email = _email;
    if (email.isEmpty) {
      setState(() => _error = 'Email missing. Please start again.');
      return;
    }
    if (_code.length != 6) {
      setState(() => _error = 'Please enter the complete 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resetToken = await mindeaseApi.verifyOtp(email, _code);
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _busy = false);
      context.go(
        '/forgot-password/reset?email=${Uri.encodeComponent(email)}&token=${Uri.encodeComponent(resetToken)}',
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
        _error = 'Unable to verify the code right now. Please try again.';
      });
    }
  }

  String get _timerLabel {
    final s = _remaining.inSeconds;
    return 'Resend code in ${(s ~/ 60).toString().padLeft(2, '0')}'
        ':${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResend = _remaining == Duration.zero;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Code')),
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
                        Icons.password_rounded,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Enter the 6-digit code',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'We sent a verification code to your registered email.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_error != null) ...[
                      FormErrorBanner(message: _error!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppOtpField(
                      length: 6,
                      enabled: !_busy,
                      onChanged: (value) => setState(() => _code = value),
                      onCompleted: (_) => _verify(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (canResend)
                          TextButton.icon(
                            onPressed: _resend,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Resend Code'),
                          )
                        else
                          Flexible(
                            child: Text(
                              _timerLabel,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: 'Verify Code',
                      loading: _busy,
                      onPressed: _verify,
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
