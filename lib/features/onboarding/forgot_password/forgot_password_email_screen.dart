import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_error_banner.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordEmailScreen extends StatefulWidget {
  const ForgotPasswordEmailScreen({super.key});

  @override
  State<ForgotPasswordEmailScreen> createState() =>
      _ForgotPasswordEmailScreenState();
}

class _ForgotPasswordEmailScreenState extends State<ForgotPasswordEmailScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();

  String? _emailError;
  String? _formError;
  bool _submitting = false;
  bool _touched = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _touched = true;
    final error = Validators.email(_emailController.text);
    setState(() {
      _emailError = error;
      _formError = null;
    });
    if (error != null) return;
    setState(() => _submitting = true);
    final otp = await _auth.sendResetOtp(_emailController.text.trim());
    if (!mounted) return;
    AppSnackbar.show(context, 'Verification code sent. Demo OTP: $otp');
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(
        builder: (_) =>
            OtpVerificationScreen(email: _emailController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPage(
      title: 'Forgot Password',
      subtitle:
          'Enter your registered email address and we will send you a verification code.',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: AppButton(
        label: 'Send Verification Code',
        icon: Icons.mark_email_read_outlined,
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
            controller: _emailController,
            label: 'Email Address',
            hintText: 'you@example.com',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            errorText: _touched ? _emailError : null,
            enabled: !_submitting,
            onChanged: (_) {
              if (_touched) {
                setState(
                  () => _emailError = Validators.email(_emailController.text),
                );
              }
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}
