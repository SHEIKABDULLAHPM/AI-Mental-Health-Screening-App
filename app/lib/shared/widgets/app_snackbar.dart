import 'package:flutter/material.dart';

/// Snackbar helpers for consistent toasts.
abstract final class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    final theme = Theme.of(context);
    final color = error ? theme.colorScheme.error : null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
        ),
      );
  }
}
