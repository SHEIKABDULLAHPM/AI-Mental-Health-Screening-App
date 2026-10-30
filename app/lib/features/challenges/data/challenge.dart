import 'package:flutter/material.dart';

/// Lifecycle state of a challenge instance, mirroring the server state machine.
enum ChallengeStatus {
  available,
  active,
  inProgress,
  completed,
  expired;

  static ChallengeStatus fromJson(String? value) {
    switch (value?.toUpperCase()) {
      case 'ACTIVE':
        return ChallengeStatus.active;
      case 'IN_PROGRESS':
        return ChallengeStatus.inProgress;
      case 'COMPLETED':
        return ChallengeStatus.completed;
      case 'EXPIRED':
        return ChallengeStatus.expired;
      default:
        return ChallengeStatus.available;
    }
  }
}

/// A wellness challenge with the user's current, server-derived progress.
class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    this.why,
    required this.type,
    required this.frequency,
    this.category,
    this.difficulty,
    this.estimatedDuration,
    required this.target,
    required this.durationDays,
    required this.points,
    this.reward,
    this.badgeCode,
    required this.status,
    required this.progress,
    this.streak = 0,
    this.bestStreak = 0,
    this.startedAt,
    this.expiresAt,
    this.completedAt,
    this.personalizationReason,
  });

  final String id;
  final String title;
  final String description;
  final String? why;
  final String type;
  final String frequency;
  final String? category;
  final String? difficulty;
  final String? estimatedDuration;
  final int target;
  final int durationDays;
  final int points;
  final String? reward;
  final String? badgeCode;
  final ChallengeStatus status;
  final int progress;
  final int streak;
  final int bestStreak;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? completedAt;
  final String? personalizationReason;

  bool get isGameChallenge => type == 'GAME_ACTIVITY';

  bool get isCompleted => status == ChallengeStatus.completed;
  bool get isExpired => status == ChallengeStatus.expired;
  bool get isActive => status == ChallengeStatus.active;
  bool get isInProgress => status == ChallengeStatus.inProgress;
  bool get isOpen => status == ChallengeStatus.active || status == ChallengeStatus.inProgress;

  int get remaining => (target - progress).clamp(0, target);

  /// Progress as a 0.0–1.0 fraction, capped at 1.0. Derived from server values.
  double get progressFraction => target <= 0
      ? 0.0
      : (progress / target).clamp(0.0, 1.0);

  int get percentage => (progressFraction * 100).round();

  String get statusLabel => switch (status) {
        ChallengeStatus.available => 'Available',
        ChallengeStatus.active => 'Active',
        ChallengeStatus.inProgress => 'In progress',
        ChallengeStatus.completed => 'Completed',
        ChallengeStatus.expired => 'Expired',
      };

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        why: json['why'] as String?,
        type: json['type'] as String? ?? '',
        frequency: json['frequency'] as String? ?? '',
        category: json['category'] as String?,
        difficulty: json['difficulty'] as String?,
        estimatedDuration: json['estimatedDuration'] as String?,
        target: (json['target'] as num?)?.toInt() ?? 1,
        durationDays: (json['durationDays'] as num?)?.toInt() ?? 1,
        points: (json['points'] as num?)?.toInt() ?? 0,
        reward: json['reward'] as String?,
        badgeCode: json['badgeCode'] as String?,
        status: ChallengeStatus.fromJson(json['status'] as String?),
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['bestStreak'] as num?)?.toInt() ?? 0,
        startedAt: _parseDate(json['startedAt']),
        expiresAt: _parseDate(json['expiresAt']),
        completedAt: _parseDate(json['completedAt']),
        personalizationReason: json['personalizationReason'] as String?,
      );

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// A badge earned by the user, as reported by the server.
class ChallengeBadge {
  const ChallengeBadge({
    required this.code,
    required this.label,
    this.challengeId,
    this.earnedAt,
    this.icon = Icons.emoji_events_rounded,
  });

  final String code;
  final String label;
  final String? challengeId;
  final DateTime? earnedAt;
  final IconData icon;

  factory ChallengeBadge.fromJson(Map<String, dynamic> json) => ChallengeBadge(
        code: json['code'] as String? ?? '',
        label: json['label'] as String? ?? 'Badge',
        challengeId: json['challengeId'] as String?,
        earnedAt: json['earnedAt'] != null
            ? DateTime.tryParse(json['earnedAt'].toString())
            : null,
      );
}
