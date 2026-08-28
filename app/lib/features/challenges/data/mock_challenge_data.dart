import 'package:flutter/material.dart';

import 'package:mindease/features/challenges/data/challenge.dart';

/// UI-ONLY mock challenges — linked to habits and streaks later.
const List<Challenge> kChallenges = [
  Challenge(
    id: 'ch1',
    title: 'Gratitude week',
    description:
        'Write down three things you are grateful for every evening for one '
        'week.',
    durationDays: 7,
    points: 50,
    currentDay: 4,
  ),
  Challenge(
    id: 'ch2',
    title: '7-day calm',
    description:
        'Complete one breathing or meditation session each day for 7 days.',
    durationDays: 7,
    points: 70,
    currentDay: 2,
  ),
  Challenge(
    id: 'ch3',
    title: 'Move your body',
    description:
        'A short walk, stretch or workout each day for 5 days to lift your '
        'energy.',
    durationDays: 5,
    points: 60,
  ),
  Challenge(
    id: 'ch4',
    title: 'Sleep reset',
    description:
        'Wind down 30 minutes earlier and keep a consistent bedtime for a '
        'week.',
    durationDays: 7,
    points: 80,
    isCompleted: true,
  ),
];

const List<ChallengeBadge> kChallengeBadges = [
  ChallengeBadge(label: 'First step', icon: Icons.flag_rounded),
  ChallengeBadge(label: '3-day streak', icon: Icons.local_fire_department_rounded),
  ChallengeBadge(label: 'Half way', icon: Icons.track_changes_rounded),
  ChallengeBadge(label: 'Completed', icon: Icons.emoji_events_rounded),
];
