import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_checkbox_tile.dart';
import '../../../core/widgets/app_section_card.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../permissions/permissions_screen.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _acceptPrivacy = false;
  bool _acceptTerms = false;
  bool _acceptAi = false;
  bool _acceptStorage = false;

  bool get _allAccepted =>
      _acceptPrivacy && _acceptTerms && _acceptAi && _acceptStorage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OnboardingPage(
      title: 'Privacy & Consent',
      subtitle:
          'We want you to feel safe. Please review and accept how we handle your data before starting your screening.',
      stepLabel: 'Step 3 of 7',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Accept & Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _allAccepted
                ? () => Navigator.of(context).pushReplacement(
                    SmoothPageRoute(builder: (_) => const PermissionsScreen()),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Back',
            variant: AppButtonVariant.outline,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PolicyCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            body:
                'We collect only the information you choose to share, and we never sell your personal data. You stay in control of your information at all times.',
          ),
          const _PolicyCard(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            body:
                'MindEase is a wellness support tool. By using the app you agree to use it responsibly and not in an emergency situation.',
          ),
          const _PolicyCard(
            icon: Icons.psychology_outlined,
            title: 'AI Disclaimer',
            body:
                'Screening results and insights are AI-generated guidance, not a medical diagnosis. Always consult a qualified professional for clinical advice.',
          ),
          const _PolicyCard(
            icon: Icons.inventory_2_outlined,
            title: 'Data Collection',
            body:
                'We store your screening responses, lifestyle details and progress to personalize your guidance and improve your experience.',
          ),
          const _PolicyCard(
            icon: Icons.shield_outlined,
            title: 'Secure Storage',
            body:
                'Your data is encrypted, stored securely, and kept private on your device. You can delete your data at any time.',
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Confirm your consent',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCheckboxTile(
            value: _acceptPrivacy,
            onChanged: (v) => setState(() => _acceptPrivacy = v ?? false),
            title: 'I have read and accept the Privacy Policy',
          ),
          const SizedBox(height: AppSpacing.md),
          AppCheckboxTile(
            value: _acceptTerms,
            onChanged: (v) => setState(() => _acceptTerms = v ?? false),
            title: 'I agree to the Terms & Conditions',
          ),
          const SizedBox(height: AppSpacing.md),
          AppCheckboxTile(
            value: _acceptAi,
            onChanged: (v) => setState(() => _acceptAi = v ?? false),
            title: 'I consent to AI analysis of my responses',
          ),
          const SizedBox(height: AppSpacing.md),
          AppCheckboxTile(
            value: _acceptStorage,
            onChanged: (v) => setState(() => _acceptStorage = v ?? false),
            title: 'I consent to secure storage of my data',
          ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppSectionCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
