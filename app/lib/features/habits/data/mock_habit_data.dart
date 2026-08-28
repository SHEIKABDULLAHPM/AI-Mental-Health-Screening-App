import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/features/habits/data/habit.dart';

/// UI-ONLY mock habits — synced to real tracking later.
const List<Habit> kHabits = [
  Habit(
    id: 'h1',
    title: 'Sleep well',
    icon: Icons.bedtime_rounded,
    color: AppColors.primary,
    goalLabel: '8 hours',
    unit: 'night',
    streak: 5,
    doneToday: true,
    week: [true, true, false, true, true, true, true],
  ),
  Habit(
    id: 'h2',
    title: 'Meditate',
    icon: Icons.self_improvement_rounded,
    color: Color(0xFF7C6BF0),
    goalLabel: '15 minutes',
    unit: 'session',
    streak: 3,
    doneToday: false,
    week: [true, false, true, false, true, true, false],
  ),
  Habit(
    id: 'h3',
    title: 'Move your body',
    icon: Icons.directions_walk_rounded,
    color: Color(0xFF2BB673),
    goalLabel: '30 minutes',
    unit: 'workout',
    streak: 7,
    doneToday: true,
    week: [true, true, true, true, true, true, true],
  ),
  Habit(
    id: 'h4',
    title: 'Drink water',
    icon: Icons.water_drop_rounded,
    color: Color(0xFF37A2E8),
    goalLabel: '8 glasses',
    unit: 'glass',
    streak: 12,
    doneToday: true,
    week: [true, true, true, true, true, true, true],
  ),
  Habit(
    id: 'h5',
    title: 'Screen-free wind-down',
    icon: Icons.phone_iphone_rounded,
    color: Color(0xFFF2727C),
    goalLabel: '30 minutes',
    unit: 'session',
    streak: 2,
    doneToday: false,
    week: [false, false, true, false, true, false, false],
  ),
];

const List<IconData> kHabitIcons = [
  Icons.bedtime_rounded,
  Icons.self_improvement_rounded,
  Icons.directions_walk_rounded,
  Icons.water_drop_rounded,
  Icons.phone_iphone_rounded,
  Icons.music_note_rounded,
  Icons.sports_rounded,
  Icons.book_rounded,
  Icons.restaurant_rounded,
];

const List<Color> kHabitColors = [
  AppColors.primary,
  Color(0xFF7C6BF0),
  Color(0xFF2BB673),
  Color(0xFF37A2E8),
  Color(0xFFF2727C),
  Color(0xFFF2A93B),
];
