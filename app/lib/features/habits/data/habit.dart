import 'package:flutter/material.dart';

/// A tracked wellness habit (UI-only phase model).
class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.goalLabel,
    this.unit = 'session',
    this.streak = 0,
    this.doneToday = false,
    this.week = const [false, false, false, false, false, false, false],
  });

  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final String goalLabel;
  final String unit;
  final int streak;
  final bool doneToday;

  /// Completion status for the last 7 days (oldest → today).
  final List<bool> week;

  int get completedThisWeek => week.where((d) => d).length;

  double get weekRate =>
      week.isEmpty ? 0 : completedThisWeek / week.length;

  Habit copyWith({bool? doneToday, int? streak, List<bool>? week}) => Habit(
        id: id,
        title: title,
        icon: icon,
        color: color,
        goalLabel: goalLabel,
        unit: unit,
        streak: streak ?? this.streak,
        doneToday: doneToday ?? this.doneToday,
        week: week ?? this.week,
      );
}
