import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import 'package:mindease/core/config/server_endpoint.dart';
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
  String _serverUrl = '';
  bool _testingServer = false;
  bool? _serverReachable;

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
      _serverUrl = ServerEndpoint.current;
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

  Future<void> _testServer() async {
    setState(() {
      _testingServer = true;
      _serverReachable = null;
    });
    final reachable = await ServerEndpoint.probe();
    if (!mounted) return;
    setState(() {
      _testingServer = false;
      _serverReachable = reachable;
    });
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: _serverUrl);
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Server address'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Backend base URL',
                    hintText: '192.168.1.4:8080',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'A host or host:port is enough; http:// and /api/v1 are\n'
                  'added when missing.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = ServerEndpoint.normalize(controller.text);
                  if (value == null) {
                    setDialogState(() {
                      error = 'Enter a host such as 192.168.1.4:8080';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (saved == null) return;
    await ServerEndpoint.save(saved);
    if (!mounted) return;
    setState(() {
      _serverUrl = ServerEndpoint.current;
      _serverReachable = null;
    });
  }

  Future<void> _resetServer() async {
    await ServerEndpoint.reset();
    if (!mounted) return;
    setState(() {
      _serverUrl = ServerEndpoint.current;
      _serverReachable = null;
    });
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
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Server connection',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Every request goes to the address below. Point it at the \n'
                'host running the backend when this device cannot reach the \n'
                'build default.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSectionCard(
                icon: Icons.dns_outlined,
                iconColor: theme.colorScheme.primary,
                title: ServerEndpoint.isOverridden
                    ? 'Custom address'
                    : 'Build default',
                subtitle: _serverUrl,
                children: [
                  if (_serverReachable != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _serverReachable!
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          size: 18,
                          color: _serverReachable!
                              ? AppColors.success
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _serverReachable!
                                ? 'Server is up at '
                                    '${ServerEndpoint.healthUri()}.'
                                : 'No answer from '
                                    '${ServerEndpoint.healthUri()}. Check the '
                                    'server is running and this phone is on '
                                    'the same network.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  AppButton(
                    label: 'Test connection',
                    variant: AppButtonVariant.outlined,
                    icon: Icons.wifi_tethering_rounded,
                    loading: _testingServer,
                    onPressed: _testingServer ? null : _testServer,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Change address',
                    variant: AppButtonVariant.outlined,
                    icon: Icons.edit_outlined,
                    onPressed: _editServer,
                  ),
                  if (ServerEndpoint.isOverridden) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Use build default',
                      variant: AppButtonVariant.outlined,
                      onPressed: _resetServer,
                    ),
                  ],
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
