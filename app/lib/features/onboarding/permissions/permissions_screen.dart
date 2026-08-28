import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mindease/core/permissions/permissions_service.dart';
import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';

/// Requests the permissions the screening & support features need, sourcing
/// the granted state from the OS via [PermissionsService].
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final Set<String> _granted = {};
  String? _granting;
  bool _busy = false;

  List<PermissionEntry> get _permissions => PermissionsService.entries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFromOs());
  }

  /// Seeds the in-memory granted set from the OS so the screen truthfully
  /// reflects permissions the user already allowed in system Settings.
  Future<void> _refreshFromOs() async {
    try {
      final statuses = await PermissionsService.statuses();
      if (!mounted) return;
      setState(() {
        for (final p in _permissions) {
          final s = statuses[p.id];
          if (s != null && s.isGranted) _granted.add(p.id);
        }
      });
    } catch (_) {
      // Platform unavailable (e.g. widget tests): leave state as-is.
    }
  }

  Future<void> _allow(PermissionEntry p) async {
    setState(() => _granting = p.id);
    final status = await PermissionsService.request(p.id);
    final granted = status.isGranted;
    if (!mounted) return;
    setState(() {
      _granting = null;
      if (granted) {
        _granted.add(p.id);
      } else if (status.isPermanentlyDenied) {
        _granted.remove(p.id);
      }
    });
    if (!mounted) return;
    if (!granted && status.isPermanentlyDenied) {
      await _showPermanentlyDeniedSheet(p);
    }
  }

  Future<void> _showPermanentlyDeniedSheet(PermissionEntry p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${p.title} permission is required',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You turned this off in the system settings and we won’t '
                'be able to ask again. Tap below to open Settings and '
                're-enable "${p.title}" so the feature can work.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Open Settings',
                onPressed: () {
                  Navigator.of(context).pop();
                  PermissionsService.openAppSettingsSheet();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Not now',
                variant: AppButtonVariant.outlined,
                expanded: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _continue() async {
    final statuses = await PermissionsService.statuses();
    final allGranted =
        _permissions.every((p) => statuses[p.id]?.isGranted ?? false);
    if (!allGranted) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 600));
    final prefs = await AppPreferences.load();
    await prefs.setPermissionsGranted(true);
    _granted
      ..clear()
      ..addAll(statuses.keys.where((id) => statuses[id]!.isGranted));
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
                                        borderRadius:
                                            BorderRadius.circular(99),
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
