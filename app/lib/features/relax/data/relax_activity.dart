import 'package:flutter/material.dart';

/// A relaxation / healing activity (UI-only phase model).
class RelaxActivity {
  const RelaxActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.duration,
    required this.icon,
  });

  final String id;
  final String title;
  final String description;
  final RelaxCategory category;
  final Duration duration;
  final IconData icon;
}

enum RelaxCategory { breathing, meditation, music, sounds }

extension RelaxCategoryX on RelaxCategory {
  String get label => switch (this) {
        RelaxCategory.breathing => 'Breathing',
        RelaxCategory.meditation => 'Meditation',
        RelaxCategory.music => 'Music',
        RelaxCategory.sounds => 'Sounds',
      };

  IconData get icon => switch (this) {
        RelaxCategory.breathing => Icons.air_rounded,
        RelaxCategory.meditation => Icons.self_improvement_rounded,
        RelaxCategory.music => Icons.music_note_rounded,
        RelaxCategory.sounds => Icons.graphic_eq_rounded,
      };
}
