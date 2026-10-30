import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/features/challenges/data/challenge_api.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/features/challenges/presentation/widgets/challenge_card.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';

// ── Minimal ChallengeApi stub ──

class StubChallengeApi implements ChallengeApi {
  Map<String, dynamic>? _home;
  Map<String, dynamic>? _details;
  String? _error;

  void setHome(Map<String, dynamic> home) => _home = home;
  void setDetails(Map<String, dynamic> details) => _details = details;
  void setError(String? error) => _error = error;

  void _maybeThrow() {
    if (_error != null) throw Exception(_error);
  }

  @override
  Future<Map<String, dynamic>> getChallengeHome() async {
    _maybeThrow();
    return _home ?? {};
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableChallenges() async {
    _maybeThrow();
    return const [];
  }

  @override
  Future<Map<String, dynamic>> getChallenge(String id) async {
    _maybeThrow();
    return _details ?? {};
  }

  @override
  Future<Map<String, dynamic>> startChallenge(String id) async {
    _maybeThrow();
    return _details ?? {};
  }

  @override
  Future<List<Map<String, dynamic>>> getBadges() async {
    _maybeThrow();
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getChallengeHistory({int page = 0, int size = 20}) async {
    _maybeThrow();
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveProgress() async {
    _maybeThrow();
    return const [];
  }

  @override
  Future<Map<String, dynamic>> submitGameResult({
    required String challengeId,
    required String gameType,
    required int score,
    required bool completed,
    int moves = 0,
    int durationSeconds = 0,
    String? difficulty,
  }) async {
    _maybeThrow();
    return _details ?? {};
  }

  @override
  Future<Map<String, dynamic>> submitProgress({
    required String challengeId,
    required String sourceRecordId,
  }) async {
    _maybeThrow();
    return _details ?? {};
  }
}

Map<String, dynamic> _challengeJson({
  String status = 'ACTIVE',
  int progress = 0,
  int target = 3,
}) =>
    {
      'id': 'ch-1',
      'title': 'Daily Check-in',
      'description': 'Log your mood each day.',
      'why': 'Consistency builds awareness.',
      'type': 'MOOD_CHECK_IN',
      'frequency': 'DAILY',
      'target': target,
      'durationDays': 7,
      'points': 50,
      'reward': '50 pts',
      'badgeCode': 'B_MOOD_7',
      'status': status,
      'progress': progress,
      'remaining': (target - progress).clamp(0, target),
      'percentage': target <= 0 ? 0.0 : (progress / target * 100),
      'streak': 0,
      'personalizationReason': 'You log your mood regularly.',
    };

void main() {
  group('Challenge.fromJson', () {
    test('maps full server payload', () {
      final c = Challenge.fromJson(_challengeJson(progress: 2, target: 3));
      expect(c.id, 'ch-1');
      expect(c.title, 'Daily Check-in');
      expect(c.status, ChallengeStatus.active);
      expect(c.progress, 2);
      expect(c.target, 3);
      expect(c.remaining, 1);
      expect(c.percentage, 67);
      expect(c.frequency, 'DAILY');
    });

    test('derives enum from status strings', () {
      expect(Challenge.fromJson(_challengeJson(status: 'AVAILABLE')).status,
          ChallengeStatus.available);
      expect(Challenge.fromJson(_challengeJson(status: 'IN_PROGRESS')).status,
          ChallengeStatus.inProgress);
      expect(Challenge.fromJson(_challengeJson(status: 'COMPLETED')).status,
          ChallengeStatus.completed);
      expect(Challenge.fromJson(_challengeJson(status: 'EXPIRED')).status,
          ChallengeStatus.expired);
    });

    test('clamps percentage to 100 and never exceeds target', () {
      final c = Challenge.fromJson(
        _challengeJson(progress: 5, target: 3),
      );
      expect(c.progressFraction, 1.0);
      expect(c.percentage, 100);
      expect(c.remaining, 0);
    });
  });

  group('ChallengeController', () {
    late StubChallengeApi api;
    late ChallengeController ctrl;

    setUp(() {
      api = StubChallengeApi();
      ctrl = ChallengeController(api);
    });

    test('loadHome populates active, badges, streak and recommended', () async {
      api.setHome({
        'active': [_challengeJson()],
        'completed': [_challengeJson(status: 'COMPLETED')],
        'badges': [
          {'code': 'B_MOOD_7', 'label': '7-Day Streak'},
        ],
        'currentStreak': 3,
        'pointsEarned': 120,
        'recommended': _challengeJson(status: 'AVAILABLE'),
      });

      await ctrl.loadHome();

      expect(ctrl.loaded, isTrue);
      expect(ctrl.loading, isFalse);
      expect(ctrl.error, isNull);
      expect(ctrl.active.length, 1);
      expect(ctrl.completed.length, 1);
      expect(ctrl.badges.length, 1);
      expect(ctrl.badges.first.label, '7-Day Streak');
      expect(ctrl.currentStreak, 3);
      expect(ctrl.pointsEarned, 120);
      expect(ctrl.recommended, isNotNull);
      expect(ctrl.recommended!.status, ChallengeStatus.available);
    });

    test('loadHome surface error and leaves data empty', () async {
      api.setError('boom');
      await ctrl.loadHome();
      expect(ctrl.error, isNotNull);
      expect(ctrl.loaded, isFalse);
      expect(ctrl.loading, isFalse);
    });

    test('startChallenge updates current challenge and refreshes home',
        () async {
      api.setHome({
        'active': [_challengeJson(status: 'IN_PROGRESS')],
        'badges': [],
        'currentStreak': 0,
        'pointsEarned': 0,
      });
      api.setDetails(_challengeJson(status: 'IN_PROGRESS'));

      await ctrl.startChallenge('ch-1');

      expect(ctrl.currentChallenge, isNotNull);
      expect(ctrl.currentChallenge!.status, ChallengeStatus.inProgress);
      expect(ctrl.active.length, 1);
    });

    test('loadDetails maps a single challenge', () async {
      api.setDetails(_challengeJson(status: 'COMPLETED', progress: 3));
      await ctrl.loadDetails('ch-1');
      expect(ctrl.currentChallenge!.isCompleted, isTrue);
      expect(ctrl.currentChallenge!.percentage, 100);
    });

    test('loadHome skips reload when already loaded and refresh is false',
        () async {
      api.setHome({
        'active': [_challengeJson()],
        'badges': [],
        'currentStreak': 0,
        'pointsEarned': 0,
      });

      await ctrl.loadHome();
      expect(ctrl.loaded, isTrue);

      // Second call with refresh=false should not hit API
      await ctrl.loadHome();
      expect(ctrl.loaded, isTrue);
      expect(ctrl.loading, isFalse);
    });

    test('loadHome with refresh=true forces reload', () async {
      api.setHome({
        'active': [],
        'badges': [],
        'currentStreak': 0,
        'pointsEarned': 0,
      });
      await ctrl.loadHome();
      expect(ctrl.loaded, isTrue);
      expect(ctrl.active, isEmpty);

      // Update API data and refresh
      api.setHome({
        'active': [_challengeJson()],
        'badges': [],
        'currentStreak': 5,
        'pointsEarned': 50,
      });
      await ctrl.loadHome(refresh: true);
      expect(ctrl.active.length, 1);
      expect(ctrl.currentStreak, 5);
    });

    test('loadHome handles empty home payload gracefully', () async {
      api.setHome({});
      await ctrl.loadHome();
      expect(ctrl.loaded, isTrue);
      expect(ctrl.active, isEmpty);
      expect(ctrl.completed, isEmpty);
      expect(ctrl.badges, isEmpty);
      expect(ctrl.recommended, isNull);
    });

    test('startChallenge surfaces error on failure', () async {
      api.setError('network error');
      await ctrl.startChallenge('ch-1');
      expect(ctrl.error, isNotNull);
      // Non-Failure exceptions are mapped to generic message
      expect(ctrl.error, isNotEmpty);
      expect(ctrl.loading, isFalse);
    });

    test('loadDetails surfaces error on failure', () async {
      api.setError('not found');
      await ctrl.loadDetails('missing');
      expect(ctrl.error, isNotNull);
      // Non-Failure exceptions are mapped to generic message
      expect(ctrl.error, isNotEmpty);
      expect(ctrl.loading, isFalse);
    });
  });

  group('ChallengeBadge.fromJson', () {
    test('maps full badge payload', () {
      final b = ChallengeBadge.fromJson({
        'code': 'MOOD_5',
        'label': 'Mood Consistency',
        'challengeId': 'ch-1',
        'earnedAt': '2026-08-28T12:00:00Z',
      });
      expect(b.code, 'MOOD_5');
      expect(b.label, 'Mood Consistency');
      expect(b.challengeId, 'ch-1');
      expect(b.earnedAt, isNotNull);
    });

    test('handles missing optional fields', () {
      final b = ChallengeBadge.fromJson({});
      expect(b.code, '');
      expect(b.label, 'Badge');
      expect(b.challengeId, isNull);
      expect(b.earnedAt, isNull);
    });
  });

  group('Challenge model edge cases', () {
    test('handles null/missing JSON fields gracefully', () {
      final c = Challenge.fromJson({});
      expect(c.id, '');
      expect(c.title, '');
      expect(c.description, '');
      expect(c.type, '');
      expect(c.frequency, '');
      expect(c.target, 1);
      expect(c.status, ChallengeStatus.available);
      expect(c.progress, 0);
      expect(c.streak, 0);
    });

    test('isOpen is true for active and inProgress', () {
      final active = Challenge.fromJson(_challengeJson(status: 'ACTIVE'));
      final inProgress = Challenge.fromJson(_challengeJson(status: 'IN_PROGRESS'));
      final completed = Challenge.fromJson(_challengeJson(status: 'COMPLETED'));
      final expired = Challenge.fromJson(_challengeJson(status: 'EXPIRED'));

      expect(active.isOpen, isTrue);
      expect(inProgress.isOpen, isTrue);
      expect(completed.isOpen, isFalse);
      expect(expired.isOpen, isFalse);
    });

    test('remaining is clamped to 0 when progress exceeds target', () {
      final c = Challenge.fromJson(_challengeJson(progress: 10, target: 3));
      expect(c.remaining, 0);
    });

    test('statusLabel returns correct text', () {
      for (final status in ChallengeStatus.values) {
        final c = Challenge.fromJson(_challengeJson(
            status: status.name));
        expect(c.statusLabel, isNotEmpty);
      }
    });
  });

  group('ChallengeCard widget', () {
    testWidgets('renders challenge title and progress', (tester) async {
      final challenge = Challenge.fromJson(
          _challengeJson(status: 'IN_PROGRESS', progress: 2, target: 5));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChallengeCard(
            challenge: challenge,
            onTap: () {},
          ),
        ),
      ));

      expect(find.text('Daily Check-in'), findsOneWidget);
      expect(find.byType(AppProgressBar), findsOneWidget);
    });

    testWidgets('renders completed state without progress bar', (tester) async {
      final challenge = Challenge.fromJson(_challengeJson(status: 'COMPLETED'));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChallengeCard(
            challenge: challenge,
            onTap: () {},
          ),
        ),
      ));

      expect(find.text('Daily Check-in'), findsOneWidget);
      expect(find.byType(AppProgressBar), findsNothing);
      expect(find.textContaining('Done'), findsOneWidget);
    });
  });
}
