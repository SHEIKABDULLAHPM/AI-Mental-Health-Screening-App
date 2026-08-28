import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_colors.dart';

/// Mood scale used by Mood Tracking and the daily Check-in.
class Mood {
  const Mood({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  /// 1 (most negative) to 6 (most positive) for trend math.
  final int value;

  bool get isPositive => value >= 5;
  bool get isNegative => value <= 2;
}

/// The six moods of the core mood scale (id order matters: left = positive).
const List<Mood> kMoods = [
  Mood(
    id: 'very_happy',
    label: 'Great',
    icon: Icons.sentiment_very_satisfied_rounded,
    color: AppColors.success,
    value: 6,
  ),
  Mood(
    id: 'happy',
    label: 'Good',
    icon: Icons.sentiment_satisfied_alt_rounded,
    color: Color(0xFF6FBF73),
    value: 5,
  ),
  Mood(
    id: 'calm',
    label: 'Calm',
    icon: Icons.self_improvement_rounded,
    color: AppColors.primary,
    value: 5,
  ),
  Mood(
    id: 'okay',
    label: 'Okay',
    icon: Icons.sentiment_neutral_rounded,
    color: AppColors.warning,
    value: 4,
  ),
  Mood(
    id: 'low',
    label: 'Low',
    icon: Icons.sentiment_dissatisfied_rounded,
    color: Color(0xFFF2903D),
    value: 2,
  ),
  Mood(
    id: 'stressed',
    label: 'Stressed',
    icon: Icons.sentiment_very_dissatisfied_rounded,
    color: AppColors.error,
    value: 1,
  ),
];

/// Standard emotion tags offered when recording a mood.
const List<String> kMoodEmotions = [
  'Grateful',
  'Relaxed',
  'Content',
  'Hopeful',
  'Tired',
  'Anxious',
  'Irritated',
  'Lonely',
  'Overwhelmed',
  'Sad',
];

Mood moodById(String id) =>
    kMoods.firstWhere((m) => m.id == id, orElse: () => kMoods[3]);
