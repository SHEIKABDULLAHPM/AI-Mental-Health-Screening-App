import 'package:flutter/material.dart';

/// A personalized wellness recommendation from the backend.
class Recommendation {
  const Recommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.type,
    this.reason,
    this.duration,
    this.difficulty,
    this.contentReference,
    this.contentVersion = 1,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String? type;
  final String? reason;
  final String? duration;
  final String? difficulty;
  final String? contentReference;
  final int contentVersion;

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? 'personalized',
        type: json['type'] as String?,
        reason: json['reason'] as String?,
        duration: json['duration'] as String?,
        difficulty: json['difficulty'] as String?,
        contentReference: json['contentReference'] as String?,
        contentVersion: (json['contentVersion'] as num?)?.toInt() ?? 1,
      );
}

enum RecommendationCategory {
  personalized,
  meditation,
  articles,
  videos,
  exercises,
  music,
  sounds,
}

extension RecommendationCategoryX on RecommendationCategory {
  String get label => switch (this) {
        RecommendationCategory.personalized => 'For you',
        RecommendationCategory.meditation => 'Meditation',
        RecommendationCategory.articles => 'Articles',
        RecommendationCategory.videos => 'Videos',
        RecommendationCategory.exercises => 'Exercises',
        RecommendationCategory.music => 'Music',
        RecommendationCategory.sounds => 'Sounds',
      };

  IconData get icon => switch (this) {
        RecommendationCategory.personalized => Icons.auto_awesome_rounded,
        RecommendationCategory.meditation => Icons.self_improvement_rounded,
        RecommendationCategory.articles => Icons.article_outlined,
        RecommendationCategory.videos => Icons.ondemand_video_rounded,
        RecommendationCategory.exercises => Icons.fitness_center_rounded,
        RecommendationCategory.music => Icons.music_note_rounded,
        RecommendationCategory.sounds => Icons.graphic_eq_rounded,
      };
}

RecommendationCategory parseCategory(String? value) {
  final raw = value ?? 'personalized';
  return RecommendationCategory.values.firstWhere(
    (c) => c.name == raw,
    orElse: () => RecommendationCategory.personalized,
  );
}
