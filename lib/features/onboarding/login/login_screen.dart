import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_error_banner.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../consent/privacy_consent_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../forgot_password/forgot_password_email_screen.dart';
import '../register/register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _rememberMe = false;
  bool _submitting = false;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _auth.getRememberMe().then((value) {
      if (mounted) setState(() => _rememberMe = value);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _showErrors => _touched;

  void _revalidate() {
    setState(() {
      _emailError = Validators.email(_emailController.text);
      _passwordError = Validators.required(
        _passwordController.text,
        field: 'Password',
      );
      _formError = null;
    });
  }

  Future<void> _submit() async {
    _touched = true;
    _revalidate();
    if (_emailError != null || _passwordError != null) return;
    setState(() {
      _submitting = true;
      _formError = null;
    });
    await _auth.setRememberMe(_rememberMe);
    final ok = await _auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _formError = 'Invalid email or password. Please try again.';
      });
      return;
    }
    final onboarded = await _auth.isOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(
        builder: (_) =>
            onboarded ? const DashboardScreen() : const PrivacyConsentScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return OnboardingPage(
      title: 'Welcome Back',
      subtitle: 'Sign in to continue your wellness journey.',
      stepLabel: 'Step 2 of 7',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: AppButton(
        label: 'Login',
        icon: Icons.login_rounded,
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
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            errorText: _showErrors ? _emailError : null,
            enabled: !_submitting,
            onChanged: (_) => _revalidate(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _passwordController,
            label: 'Password',
            hintText: 'Enter your password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            errorText: _showErrors ? _passwordError : null,
            enabled: !_submitting,
            onChanged: (_) => _revalidate(),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Switch(
                value: _rememberMe,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _rememberMe = v),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Text(
                    'Remember me',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).push(
                        SmoothPageRoute(
                          builder: (_) => const ForgotPasswordEmailScreen(),
                        ),
                      ),
                child: const Text('Forgot Password?'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'New to MindEase?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                        SmoothPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                child: const Text('Create Account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
