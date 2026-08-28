import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import 'package:mindease/core/permissions/permissions_service.dart';
import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_logout_tile.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';

/// Settings screen. Primarily exposes the app's permissions and keeps their
/// state in sync with the OS so the user can see (and fix) exactly what is
/// enabled. The granted/denied reflection always comes from
/// [PermissionsService.statuses()], never from a cached flag.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final Map<String, PermissionStatus> _statuses;
  String _username = '';
  bool _loaded = false;
  String? _refreshingId;

  @override
  void initState() {
    super.initState();
    _statuses = {for (final e in PermissionsService.entries) e.id: PermissionStatus.denied};
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>([
      PermissionsService.statuses(),
      AppPreferences.load(),
    ]);
    final statuses = results[0] as Map<String, PermissionStatus>;
    final prefs = results[1] as AppPreferences;
    if (!mounted) return;
    setState(() {
      _username = prefs.username;
      _statuses
        ..clear()
        ..addAll(statuses);
      _loaded = true;
    });
  }

  Future<void> _allow(PermissionEntry entry) async {
    setState(() => _refreshingId = entry.id);
    await PermissionsService.request(entry.id);
    if (!mounted) return;
    setState(() { _refreshingId = null; });
    await _load();
  }

  Future<void> _requestAllMissing() async {
    setState(() => _refreshingId = 'all');
    for (final entry in PermissionsService.entries) {
      final status = _statuses[entry.id] ?? PermissionStatus.denied;
      if (!status.isGranted) {
        await PermissionsService.request(entry.id);
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    setState(() { _refreshingId = null; });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grantedCount =
        _statuses.values.where((s) => s.isGranted).length;
    final anyMissing = grantedCount < PermissionsService.entries.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AppBackdrop(
        child: SafeArea(
          child: _loaded
              ? _buildContent(theme, grantedCount, anyMissing)
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    int grantedCount,
    bool anyMissing,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Permissions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$grantedCount of ${PermissionsService.entries.length} '
                'permissions granted',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Request all missing',
                loading: _refreshingId == 'all',
                onPressed: anyMissing ? _requestAllMissing : null,
              ),
              ...PermissionsService.entries.map(_buildTile),
              const SizedBox(height: AppSpacing.md),
              AppSectionCard(
                icon: Icons.open_in_full_rounded,
                iconColor: theme.colorScheme.primary,
                title: 'App settings',
                subtitle:
                    'Open system settings to manage permissions '
                    'you denied permanently.',
                children: [
                  AppButton(
                    label: 'Open system settings',
                    variant: AppButtonVariant.outlined,
                    icon: Icons.open_in_new_rounded,
                    onPressed:
                        () { PermissionsService.openAppSettingsSheet(); },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Account',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSectionCard(
                icon: Icons.person_outline_rounded,
                iconColor: theme.colorScheme.tertiary,
                title: _username.isEmpty ? 'Your account' : _username,
                subtitle: 'Signed in to your Synora account.',
                children: const [
                  SizedBox(height: AppSpacing.xs),
                  AppLogoutTile(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(PermissionEntry entry) {
    final theme = Theme.of(context);
    final status = _statuses[entry.id] ?? PermissionStatus.denied;
    final granted = status.isGranted;
    final permanent = status.isPermanentlyDenied;
    final busy = _refreshingId == entry.id;

    Widget trailing;
    if (granted) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.15),
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
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    } else if (permanent) {
      trailing = AppButton(
        label: 'Open Settings',
        expanded: false,
        onPressed: () { PermissionsService.openAppSettingsSheet(); },
      );
    } else {
      trailing = AppButton(
        label: 'Allow',
        expanded: false,
        loading: busy,
        onPressed: busy ? null : () { _allow(entry); },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: AppSectionCard(
        icon: entry.icon,
        iconColor: entry.color,
        title: entry.title,
        subtitle: entry.description,
        trailing: trailing,
      ),
    );
  }
}
