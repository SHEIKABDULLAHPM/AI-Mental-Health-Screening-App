import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  int _resends = 0;

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
    _resends++;
    setState(() => _error = null);
    _startTimer();
  }

  Future<void> _verify() async {
    if (_code.length != 6) {
      setState(() => _error = 'Please enter the complete 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    if (_resends == 0 && _code == '000000') {
      setState(() {
        _busy = false;
        _error = 'That code doesn\u2019t look right. Check and try again.';
      });
      return;
    }
    _timer?.cancel();
    context.go('/forgot-password/reset');
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
