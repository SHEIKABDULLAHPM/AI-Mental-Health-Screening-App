import 'package:flutter/material.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_checkbox_tile.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_error_banner.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../consent/privacy_consent_screen.dart';
import '../login/login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;
  bool _acceptTerms = false;
  bool _submitting = false;
  bool _touched = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _showErrors => _touched;

  void _revalidate() {
    setState(() {
      _nameError = Validators.fullName(_nameController.text);
      _emailError = Validators.email(_emailController.text);
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
    final valid =
        _nameError == null &&
        _emailError == null &&
        _passwordError == null &&
        _confirmError == null;
    if (!valid) return;
    if (!_acceptTerms) {
      setState(
        () => _formError =
            'Please accept the Terms & Privacy Policy to continue.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      final profile = UserProfile(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
      );
      await _auth.signUp(profile: profile, password: _passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        SmoothPageRoute(builder: (_) => const PrivacyConsentScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = e is AuthException
            ? e.message
            : 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strength = Validators.passwordStrength(_passwordController.text);
    final showStrength = _passwordController.text.isNotEmpty;

    return OnboardingPage(
      title: 'Create Account',
      subtitle: 'Start your journey to better mental wellbeing.',
      stepLabel: 'Step 2 of 7',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: AppButton(
        label: 'Create Account',
        icon: Icons.person_add_alt_1_rounded,
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
            controller: _nameController,
            label: 'Full Name',
            hintText: 'e.g. Alex Morgan',
            prefixIcon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            errorText: _showErrors ? _nameError : null,
            enabled: !_submitting,
            onChanged: (_) => _revalidate(),
          ),
          const SizedBox(height: AppSpacing.lg),
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
            hintText: 'Minimum 8 characters',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _showErrors ? _passwordError : null,
            enabled: !_submitting,
            onChanged: (_) => _revalidate(),
          ),
          if (showStrength) ...[
            const SizedBox(height: AppSpacing.sm),
            _PasswordStrengthBar(strength: strength),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppTextField(
            controller: _confirmController,
            label: 'Confirm Password',
            hintText: 'Re-enter your password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _showErrors ? _confirmError : null,
            enabled: !_submitting,
            onChanged: (_) => _revalidate(),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCheckboxTile(
            value: _acceptTerms,
            enabled: !_submitting,
            onChanged: (v) => setState(() {
              _acceptTerms = v ?? false;
              _formError = null;
            }),
            title: 'I agree to the Terms & Conditions and Privacy Policy',
            subtitle:
                'By creating an account you agree to how MindEase handles your data.',
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                        SmoothPageRoute(builder: (_) => const LoginScreen()),
                      ),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.strength});

  final ({bool length, bool uppercase, bool number, bool symbol}) strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
        final color = item.ok ? AppColors.success : scheme.onSurfaceVariant;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: item.ok
                ? AppColors.success.withValues(alpha: 0.12)
                : scheme.surfaceContainerLow,
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
