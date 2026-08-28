import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/core/utils/validators.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_checkbox_tile.dart';
import 'package:mindease/shared/widgets/app_logo.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/shared/widgets/form_error_banner.dart';

/// Account creation with full validation, loading & error states.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  final Map<String, String> _fieldErrors = {};
  String? _formError;
  bool _busy = false;
  bool _acceptedTerms = false;
  bool _showTermsError = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _validate() {
    final errors = <String, String>{
      if (Validators.required(_name.text) != null)
        'name': 'Please enter your full name',
      if (Validators.email(_email.text) != null)
        'email': Validators.email(_email.text)!,
      if (Validators.password(_password.text) != null)
        'password': Validators.password(_password.text)!,
      if (Validators.confirmPassword(_confirm.text, _password.text) != null)
        'confirm': Validators.confirmPassword(_confirm.text, _password.text)!,
    };
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _showTermsError = !_acceptedTerms;
      _formError = null;
    });
  }

  bool get _isValid => _fieldErrors.isEmpty && _acceptedTerms && !_busy;

  Future<void> _submit() async {
    _validate();
    if (!_acceptedTerms) {
      setState(() => _showTermsError = true);
    }
    if (!_isValid) return;

    setState(() => _busy = true);
    _formError = null;

    try {
      final session = await mindeaseApi.register(
        fullName: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        confirmPassword: _confirm.text,
      );
      await sessionStore.save(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      final prefs = await AppPreferences.load();
      await prefs.saveSession(username: session.user.fullName.split(' ').first);
      if (!mounted) return;
      context.go('/consent');
    } on Failure catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = 'Unable to create your account right now. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: _busy ? null : () => context.go('/welcome'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const Center(child: AppLogoMark(size: 56)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Create Account',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Start your wellbeing journey in under 5 minutes.',
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
                      controller: _name,
                      label: 'Full Name',
                      hint: 'e.g. Priya Sharma',
                      prefixIcon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      errorText: _fieldErrors['name'],
                      onChanged: (_) =>
                          setState(() => _fieldErrors.remove('name')),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _email,
                      label: 'Email Address',
                      hint: 'you@example.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      errorText: _fieldErrors['email'],
                      onChanged: (_) =>
                          setState(() => _fieldErrors.remove('email')),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _password,
                      label: 'Password',
                      hint: '8+ characters',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      errorText: _fieldErrors['password'],
                      onChanged: (_) =>
                          setState(() => _fieldErrors.remove('password')),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _confirm,
                      label: 'Confirm Password',
                      hint: 'Repeat your password',
                      prefixIcon: Icons.lock_clock_outlined,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      errorText: _fieldErrors['confirm'],
                      onChanged: (_) =>
                          setState(() => _fieldErrors.remove('confirm')),
                      onSubmitted: (_) => _busy ? null : _submit(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCheckboxTile(
                      title: 'I accept the Terms & Privacy Policy',
                      value: _acceptedTerms,
                      error: _showTermsError
                          ? 'You must accept the Terms & Privacy Policy'
                          : null,
                      onChanged: (v) => setState(() {
                        _acceptedTerms = v;
                        _showTermsError = false;
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Create Account',
                      loading: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextLink(
                      prefix: 'Already have an account?',
                      text: 'Sign In',
                      onPressed: () => context.go('/login'),
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
