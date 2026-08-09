import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';

/// Requests only the permissions the screening & support features need.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionDef {
  const _PermissionDef({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final String id;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final Set<String> _granted = {};
  String? _granting;
  bool _busy = false;

  static const _permissions = <_PermissionDef>[
    _PermissionDef(
      id: 'notifications',
      icon: Icons.notifications_active_outlined,
      title: 'Notifications',
      description: 'Gentle reminders for check-ins and daily AI insights.',
      color: Color(0xFF4F6DF5),
    ),
    _PermissionDef(
      id: 'microphone',
      icon: Icons.mic_none_rounded,
      title: 'Microphone',
      description: 'Optional voice journaling with your AI coach.',
      color: Color(0xFF8B8EE8),
    ),
    _PermissionDef(
      id: 'camera',
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      description: 'Add a profile photo and visual mood check-ins.',
      color: Color(0xFF30A46C),
    ),
    _PermissionDef(
      id: 'storage',
      icon: Icons.photo_library_outlined,
      title: 'Storage',
      description: 'Save private journal attachments on your device.',
      color: Color(0xFFE0A03E),
    ),
  ];

  Future<void> _allow(_PermissionDef p) async {
    setState(() => _granting = p.id);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      _granting = null;
      _granted.add(p.id);
    });
  }

  Future<void> _continue() async {
    if (_granted.length != _permissions.length) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 800));
    final prefs = await AppPreferences.load();
    await prefs.setPermissionsGranted(true);
    if (!mounted) return;
    context.go('/screening');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allGranted = _granted.length == _permissions.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    8,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'A little goes a long way',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'We only ask for the essentials to make your '
                            'wellness journey personal. You can change these '
                            'permissions anytime in Settings.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          for (final p in _permissions) ...[
                            AppSectionCard(
                              backgroundColor: _granted.contains(p.id)
                                  ? theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.4)
                                  : null,
                              icon: p.icon,
                              iconColor: p.color,
                              title: p.title,
                              subtitle: p.description,
                              trailing: _granted.contains(p.id)
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.check_rounded,
                                            size: 16,
                                            color: AppColors.success,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Allowed',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : _granting == p.id
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                            ),
                                          ),
                                        )
                                      : AppButton(
                                          label: 'Allow',
                                          expanded: false,
                                          onPressed: () => _allow(p),
                                        ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppButton(
                          label: allGranted
                              ? 'Continue'
                              : '${_granted.length}/${_permissions.length} permissions',
                          loading: _busy,
                          onPressed: allGranted ? _continue : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
