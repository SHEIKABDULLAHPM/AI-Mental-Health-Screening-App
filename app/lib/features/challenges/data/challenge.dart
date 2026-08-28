import 'package:flutter/material.dart';

/// A wellness challenge (UI-only phase model).
class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.durationDays,
    required this.points,
    this.isCompleted = false,
    this.currentDay = 0,
  });

  final String id;
  final String title;
  final String description;
  final int durationDays;
  final int points;
  final bool isCompleted;
  final int currentDay;

  double get progress => durationDays == 0
      ? 0
      : (currentDay.clamp(0, durationDays) / durationDays).toDouble();

  Challenge copyWith({int? currentDay, bool? isCompleted}) => Challenge(
        id: id,
        title: title,
        description: description,
        durationDays: durationDays,
        points: points,
        isCompleted: isCompleted ?? this.isCompleted,
        currentDay: currentDay ?? this.currentDay,
      );
}

class ChallengeBadge {
  const ChallengeBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const List<ChallengeBadge> kChallengeBadges = [
  ChallengeBadge(label: 'First step', icon: Icons.flag_rounded),
  ChallengeBadge(label: '3-day streak', icon: Icons.local_fire_department_rounded),
  ChallengeBadge(label: 'Half way', icon: Icons.track_changes_rounded),
  ChallengeBadge(label: 'Completed', icon: Icons.emoji_events_rounded),
];
