import 'package:flutter/material.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/habits/data/habit.dart';

/// Manages tracked wellness habits: listing, CRUD, daily toggle.
class HabitController extends ChangeNotifier {
  HabitController(this._api);

  final FeatureApi _api;

  List<Habit> _habits = [];
  Habit? _currentHabit;
  bool _loading = false;
  String? _error;

  List<Habit> get habits => _habits;
  Habit? get currentHabit => _currentHabit;
  bool get loading => _loading;
  String? get error => _error;

  void _start() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  /// Fetch all habits for the current user.
  Future<void> loadHabits() async {
    _start();
    try {
      final rows = await _api.getHabits();
      _habits = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Create a new habit and refresh the list.
  Future<void> createHabit({
    required String title,
    required int iconCodePoint,
    required int colorValue,
    required String goalLabel,
    String unit = 'session',
  }) async {
    _start();
    try {
      await _api.createHabit(
        title: title,
        iconCodePoint: iconCodePoint,
        colorValue: colorValue,
        goalLabel: goalLabel,
        unit: unit,
      );
      await loadHabits();
    } catch (e) {
      _fail(e);
    }
  }

  /// Update an existing habit and refresh the list.
  Future<void> updateHabit({
    required String id,
    String? title,
    int? iconCodePoint,
    int? colorValue,
    String? goalLabel,
    String? unit,
  }) async {
    _start();
    try {
      await _api.updateHabit(
        id: id,
        title: title,
        iconCodePoint: iconCodePoint,
        colorValue: colorValue,
        goalLabel: goalLabel,
        unit: unit,
      );
      await loadHabits();
    } catch (e) {
      _fail(e);
    }
  }

  /// Delete a habit and refresh the list.
  Future<void> deleteHabit(String id) async {
    _start();
    try {
      await _api.deleteHabit(id);
      _currentHabit = null;
      await loadHabits();
    } catch (e) {
      _fail(e);
    }
  }

  /// Toggle today's completion for a habit.
  Future<void> toggleHabit(String id) async {
    _start();
    try {
      await _api.toggleHabit(id);
      await loadHabits();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load a single habit into [currentHabit].
  Future<void> loadHabitDetails(String id) async {
    _start();
    try {
      final json = await _api.getHabit(id);
      _currentHabit = _fromApi(json);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }
}

// ──────────────────────────────────────────── API → domain mapping

Habit _fromApi(Map<String, dynamic> json) => Habit(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      icon: _iconFromCodePoint(json['iconCodePoint']),
      color: Color((json['colorValue'] as num?)?.toInt() ?? 0xFF6C63FF),
      goalLabel: json['goalLabel'] as String? ?? '',
      unit: json['unit'] as String? ?? 'session',
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      doneToday: json['doneToday'] as bool? ?? false,
      week: _parseWeek(json['week']),
    );

IconData _iconFromCodePoint(dynamic value) {
  final codePoint = (value as num?)?.toInt();
  if (codePoint == null) return Icons.check_circle_rounded;
  // ignore: non_const_argument_for_const_parameter
  return IconData(codePoint, fontFamily: 'MaterialIcons');
}

List<bool> _parseWeek(dynamic value) {
  if (value is List) {
    return value.map((e) => e == true).toList();
  }
  return const [false, false, false, false, false, false, false];
}
