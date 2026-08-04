import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/onboarding_page.dart';
import '../../../core/widgets/smooth_page_route.dart';
import '../screening/screening_screen.dart';

enum PermissionState { undecided, allowed, denied }

class _PermissionItem {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

const List<_PermissionItem> _permissions = [
  _PermissionItem(
    icon: Icons.notifications_active_outlined,
    title: 'Notifications',
    description:
        'Gentle reminders and timely check-in nudges to help you stay consistent.',
  ),
  _PermissionItem(
    icon: Icons.mic_none_rounded,
    title: 'Microphone',
    description:
        'Used only for optional voice journaling when you prefer to speak.',
  ),
  _PermissionItem(
    icon: Icons.camera_alt_outlined,
    title: 'Camera',
    description:
        'Used only if you choose to add a profile photo. Always optional.',
  ),
  _PermissionItem(
    icon: Icons.folder_outlined,
    title: 'Storage',
    description:
        'Lets the app save your reports and journal entries on your device.',
  ),
];

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final Map<int, PermissionState> _states = {
    for (var i = 0; i < _permissions.length; i++) i: PermissionState.undecided,
  };

  bool get _allResponded =>
      _states.values.every((s) => s != PermissionState.undecided);

  void _setState(int index, PermissionState state) {
    setState(() => _states[index] = state);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return OnboardingPage(
      title: 'Permissions',
      subtitle:
          'MindEase only asks for the permissions it truly needs. You can change these anytime in Settings.',
      stepLabel: 'Step 4 of 7',
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _allResponded
                ? () => Navigator.of(context).pushReplacement(
                    SmoothPageRoute(builder: (_) => const ScreeningScreen()),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_states.values.where((s) => s != PermissionState.undecided).length} of ${_permissions.length} permissions reviewed',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'All permissions are optional. You can still use MindEase even if you decline.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < _permissions.length; i++) ...[
            _PermissionCard(
              item: _permissions[i],
              state: _states[i]!,
              onAllow: () => _setState(i, PermissionState.allowed),
              onDeny: () => _setState(i, PermissionState.denied),
            ),
            if (i < _permissions.length - 1)
              const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.item,
    required this.state,
    required this.onAllow,
    required this.onDeny,
  });

  final _PermissionItem item;
  final PermissionState state;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final resolved = state == PermissionState.allowed;
    final declined = state == PermissionState.denied;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: resolved
            ? AppColors.success.withValues(alpha: 0.08)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: resolved
              ? AppColors.success.withValues(alpha: 0.4)
              : declined
              ? scheme.outlineVariant.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  item.icon,
                  color: scheme.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state == PermissionState.undecided)
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Allow',
                    variant: AppButtonVariant.tonal,
                    fullWidth: false,
                    onPressed: onAllow,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: 'Not Now',
                    variant: AppButtonVariant.outline,
                    fullWidth: false,
                    onPressed: onDeny,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  resolved
                      ? Icons.check_circle_rounded
                      : Icons.remove_circle_outline_rounded,
                  color: resolved ? AppColors.success : scheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  resolved ? 'Permission granted' : 'Skipped for now',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: resolved
                        ? AppColors.success
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
