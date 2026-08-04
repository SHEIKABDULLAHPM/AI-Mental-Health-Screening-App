import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_otp_field.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/form_error_banner.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import 'reset_password_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key, required this.email});

  final String email;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _auth = AuthService();
  String _otp = '';
  bool _verifying = false;
  bool _otpError = false;
  String? _formError;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    final otp = await _auth.sendResetOtp(widget.email);
    if (!mounted) return;
    AppSnackbar.show(context, 'New code sent. Demo OTP: $otp');
    setState(() {
      _otp = '';
      _otpError = false;
      _formError = null;
    });
    _startCountdown();
  }

  Future<void> _verify() async {
    if (_otp.length < 6) {
      setState(() {
        _otpError = true;
        _formError = 'Please enter the 6-digit code.';
      });
      return;
    }
    setState(() {
      _verifying = true;
      _formError = null;
    });
    final ok = await _auth.verifyOtp(widget.email, _otp);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _verifying = false;
        _otpError = true;
        _formError = 'Incorrect code. Please check and try again.';
      });
      return;
    }
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(builder: (_) => ResetPasswordScreen(email: widget.email)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return OnboardingPage(
      title: 'Verify Your Email',
      subtitle: 'Enter the 6-digit code we sent to ${widget.email}.',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: AppButton(
        label: 'Verify & Continue',
        icon: Icons.verified_outlined,
        loading: _verifying,
        onPressed: _verifying ? null : _verify,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_formError != null) ...[
            FormErrorBanner(message: _formError!),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppOtpField(
            length: 6,
            error: _otpError,
            onChanged: (value) {
              _otp = value;
              setState(() {
                _otpError = false;
                _formError = null;
              });
            },
            onCompleted: () => _verify(),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: _secondsLeft > 0
                ? Text(
                    'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : TextButton(
                    onPressed: _resend,
                    child: const Text('Resend Code'),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              'Check the snackbar for the demo verification code.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }
}
