import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/api/journey.dart';
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

/// Sign in with validation, loading & error states.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  final Map<String, String> _fieldErrors = {};
  String? _formError;
  bool _busy = false;
  bool _rememberMe = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final errors = <String, String>{
      if (Validators.email(_email.text) != null)
        'email': Validators.email(_email.text)!,
      if (Validators.required(_password.text) != null)
        'password': 'Enter your password',
    };
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      final session =
          await mindeaseApi.login(_email.text.trim(), _password.text);
      await sessionStore.save(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      final prefs = await AppPreferences.load();
      await prefs.saveSession(
        username: session.user.fullName.split(' ').first,
        remember: _rememberMe,
      );
      if (!mounted) return;
      final destination = await JourneyRouter.nextRoute(session.user);
      if (!mounted) return;
      context.go(destination);
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
        _formError = 'Unable to sign in right now. Please try again.';
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
                        onPressed: () => context.go('/welcome'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const Center(child: AppLogoMark(size: 56)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Welcome Back',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sign in to continue your wellness journey.',
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
                      controller: _email,
                      label: 'Email',
                      hint: 'you@example.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      errorText: _fieldErrors['email'],
                      onChanged: (_) =>
                          setState(() => _fieldErrors.remove('email')),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _password,
                      label: 'Password',
                      hint: 'Your password',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      errorText: _fieldErrors['password'],
                      onChanged: (_) =>
                          setState(() => _fieldErrors.remove('password')),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: AppCheckboxTile(
                            title: 'Remember Me',
                            value: _rememberMe,
                            onChanged: (v) =>
                                setState(() => _rememberMe = v),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextButton(
                            onPressed: () => context.go('/forgot-password'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: AppSpacing.sm,
                              ),
                              minimumSize: const Size(0, 48),
                              alignment: Alignment.centerRight,
                            ),
                            child: const Text(
                              'Forgot Password?',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Login',
                      loading: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextLink(
                      prefix: "Don't have an account?",
                      text: 'Create Account',
                      onPressed: () => context.go('/register'),
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
