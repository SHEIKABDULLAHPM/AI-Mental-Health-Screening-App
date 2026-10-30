import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/relax/data/relax_activity.dart';

/// Manages relaxation activities: listing, detail and completion tracking.
class RelaxController extends ChangeNotifier {
  RelaxController(this._api);

  final FeatureApi _api;

  List<RelaxActivity> _activities = [];
  RelaxActivity? _currentActivity;
  bool _loading = false;
  bool _disposed = false;
  String? _error;

  List<RelaxActivity> get activities => _activities;
  RelaxActivity? get currentActivity => _currentActivity;
  bool get loading => _loading;
  String? get error => _error;

  void _start() {
    _loading = true;
    _error = null;
    _deferNotify();
  }

  /// Listeners must not be notified synchronously from a loader a screen
  /// calls out of `initState`: the provider scope sits above the router, and
  /// marking it while the framework is still building that screen trips its
  /// "setState() or markNeedsBuild() called during build" assertion. State is
  /// already assigned synchronously, so the in-flight build reads the right
  /// values; this only schedules the follow-up rebuild safely.
  void _deferNotify() {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  /// Fetch all relaxation activities.
  Future<void> loadActivities() async {
    _start();
    try {
      final rows = await _api.getRelaxActivities();
      _activities = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load a single activity into [currentActivity].
  Future<void> loadById(String id) async {
    _start();
    try {
      final json = await _api.getRelaxActivity(id);
      _currentActivity = _fromApi(json);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Mark an activity as completed.
  Future<void> completeActivity(String id) async {
    _start();
    try {
      await _api.completeRelaxActivity(id);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }
}

// ──────────────────────────────────────────── API → domain mapping

RelaxActivity _fromApi(Map<String, dynamic> json) => RelaxActivity(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: _parseCategory(json['category']),
      duration: _parseDuration(json['durationMinutes']),
      icon: _iconFromCodePoint(json['iconCodePoint']),
    );

RelaxCategory _parseCategory(dynamic value) {
  final raw = (value as String?) ?? 'breathing';
  return RelaxCategory.values.firstWhere(
    (c) => c.name == raw,
    orElse: () => RelaxCategory.breathing,
  );
}

Duration _parseDuration(dynamic value) {
  final minutes = (value as num?)?.toInt() ?? 5;
  return Duration(minutes: minutes);
}

IconData _iconFromCodePoint(dynamic value) {
  final codePoint = (value as num?)?.toInt();
  if (codePoint == null) return Icons.self_improvement_rounded;
  // Use the predefined self improvement icon for known code points
  // Since we cannot determine the icon name from code point at compile time,
  // return the default self improvement icon
  return Icons.self_improvement_rounded;
}
