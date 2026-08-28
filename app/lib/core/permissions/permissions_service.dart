import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

/// A single app permission: its logical id, the [Permission]s it maps to
/// (Storage maps to the Android-13 media permissions) and the UI metadata
/// shown in both the onboarding flow and the Settings screen.
class PermissionEntry {
  const PermissionEntry({
    required this.id,
    required this.permissions,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final String id;
  final List<Permission> permissions;
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  Permission get primary => permissions.first;
}

/// Central bridge between the app's logical permission ids and
/// `permission_handler`'s [Permission]s. Used by the onboarding permissions
/// flow and the Settings screen so the granted/denied state is always sourced
/// from the OS (never a fake flag).
///
/// Note: on Android 13 (API 33) `Permission.storage` maps to
/// `READ_EXTERNAL_STORAGE`, which is ignored (it always reads as `denied` and
/// never shows a runtime dialog). The granular storage permission therefore
/// requests the media permissions (`photos`, `videos`, `audio`) instead, which
/// resolve to `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO`.
abstract final class PermissionsService {
  static final List<PermissionEntry> entries = [
    const PermissionEntry(
      id: 'notifications',
      permissions: [Permission.notification],
      icon: Icons.notifications_active_outlined,
      title: 'Notifications',
      description: 'Gentle reminders for check-ins and daily AI insights.',
      color: Color(0xFF4F6DF5),
    ),
    const PermissionEntry(
      id: 'microphone',
      permissions: [Permission.microphone],
      icon: Icons.mic_none_rounded,
      title: 'Microphone',
      description: 'Optional voice journaling with your AI coach.',
      color: Color(0xFF8B8EE8),
    ),
    const PermissionEntry(
      id: 'camera',
      permissions: [Permission.camera],
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      description: 'Add a profile photo and visual mood check-ins.',
      color: Color(0xFF30A46C),
    ),
    const PermissionEntry(
      id: 'storage',
      permissions: [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ],
      icon: Icons.photo_library_outlined,
      title: 'Storage',
      description: 'Save private journal attachments on your device.',
      color: Color(0xFFE0A03E),
    ),
  ];

  /// Returns the entry for [id], or throws for unknown ids.
  static PermissionEntry of(String id) =>
      entries.firstWhere((e) => e.id == id, orElse: () => throw StateError('unknown permission $id'));

  /// Aggregated [PermissionStatus] for every app permission, keyed by id.
  /// A multi-permission entry (e.g. storage) is `granted` only when *all* of its
  /// underlying permissions are granted.
  static Future<Map<String, PermissionStatus>> statuses() async {
    final result = <String, PermissionStatus>{};
    for (final entry in entries) {
      result[entry.id] = _aggregate(
        await Future.wait(entry.permissions.map((p) => p.status)),
      );
    }
    return result;
  }

  /// Requests the permission(s) for [id] and returns the aggregated status.
  static Future<PermissionStatus> request(String id) async {
    final entry = of(id);
    final statuses = await entry.permissions.request();
    return _aggregate(statuses.values.toList(growable: false));
  }

  /// Opens the system app-settings screen so the user can (re)grant
  /// permissions that were permanently denied ("Don't ask again").
  static Future<void> openAppSettingsSheet() => openAppSettings();

  static PermissionStatus _aggregate(List<PermissionStatus> list) {
    if (list.isEmpty) return PermissionStatus.denied;
    var granted = true;
    var permanent = false;
    for (final s in list) {
      if (!s.isGranted) granted = false;
      if (s.isPermanentlyDenied) permanent = true;
    }
    if (granted) return PermissionStatus.granted;
    if (permanent) return PermissionStatus.permanentlyDenied;
    return PermissionStatus.denied;
  }
}
