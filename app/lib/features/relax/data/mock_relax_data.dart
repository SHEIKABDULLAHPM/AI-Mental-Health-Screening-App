import 'package:flutter/material.dart';

import 'package:mindease/features/relax/data/relax_activity.dart';

/// UI-ONLY mock relaxation activities — audio/guides arrive later.
const List<RelaxActivity> kRelaxActivities = [
  RelaxActivity(
    id: 're1',
    title: 'Box breathing',
    description:
        'Breathe in, hold, out and hold — 4 counts each. Instantly calming.',
    category: RelaxCategory.breathing,
    duration: Duration(minutes: 3),
    icon: Icons.air_rounded,
  ),
  RelaxActivity(
    id: 're2',
    title: '4-7-8 breathing',
    description:
        'In for 4, hold for 7, out for 8. Great before sleep or in stress.',
    category: RelaxCategory.breathing,
    duration: Duration(minutes: 2),
    icon: Icons.air_rounded,
  ),
  RelaxActivity(
    id: 're3',
    title: 'Body scan',
    description:
        'A guided journey from your toes to your head, releasing tension.',
    category: RelaxCategory.meditation,
    duration: Duration(minutes: 10),
    icon: Icons.self_improvement_rounded,
  ),
  RelaxActivity(
    id: 're4',
    title: 'Calm mind',
    description: 'A short meditation for a racing mind and busy thoughts.',
    category: RelaxCategory.meditation,
    duration: Duration(minutes: 5),
    icon: Icons.self_improvement_rounded,
  ),
  RelaxActivity(
    id: 're5',
    title: 'Ocean waves',
    description: 'Gentle instrumental music to help you let go of the day.',
    category: RelaxCategory.music,
    duration: Duration(minutes: 15),
    icon: Icons.music_note_rounded,
  ),
  RelaxActivity(
    id: 're6',
    title: 'Rainfall',
    description: 'Soft rain ambience to focus, read or fall asleep to.',
    category: RelaxCategory.sounds,
    duration: Duration(hours: 1),
    icon: Icons.graphic_eq_rounded,
  ),
];
