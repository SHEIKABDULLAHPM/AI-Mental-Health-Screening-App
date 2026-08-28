import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_snackbar.dart';

/// Destructive "Log out" control reused from Settings and the dashboard
/// Profile tab. Confirms with the user, signs out on the server and locally,
/// then returns to the welcome screen. Surfaces failures as an error toast.
class AppLogoutTile extends StatefulWidget {
  const AppLogoutTile({super.key, this.expanded = true});

  /// When false the button shrinks to its intrinsic width (row layouts).
  final bool expanded;

  @override
  State<AppLogoutTile> createState() => _AppLogoutTileState();
}

class _AppLogoutTileState extends State<AppLogoutTile> {
  bool _busy = false;

  Future<void> _onTap() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.logout_rounded,
          color: theme.colorScheme.error,
          size: 28,
        ),
        title: const Text('Log out?'),
        content: const Text(
          'You will be signed out of your account and returned to the '
          'welcome screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await logout();
      if (!mounted) return;
      context.go('/welcome');
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackbar.show(
        context,
        'Unable to log out right now. Please try again.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Log out',
      variant: AppButtonVariant.danger,
      icon: Icons.logout_rounded,
      loading: _busy,
      expanded: widget.expanded,
      onPressed: _busy ? null : _onTap,
    );
  }
}
