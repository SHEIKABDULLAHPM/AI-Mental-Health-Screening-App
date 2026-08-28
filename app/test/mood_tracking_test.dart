import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';

// ── Minimal MoodApi stub ──

class StubMoodApi implements MoodApi {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _recent = [];
  Map<String, dynamic>? _trendsResponse;
  String? _error;

  void setEntries(List<Map<String, dynamic>> entries) => _entries = entries;
  void setRecent(List<Map<String, dynamic>> recent) => _recent = recent;
  void setTrends(Map<String, dynamic> trends) => _trendsResponse = trends;
  void setError(String? error) => _error = error;

  @override
  Future<List<Map<String, dynamic>>> getMoodEntries() async {
    if (_error != null) throw Exception(_error);
    return _entries;
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentMoodEntries({int limit = 5}) async {
    if (_error != null) throw Exception(_error);
    return _recent.take(limit).toList();
  }

  @override
  Future<Map<String, dynamic>> getMoodEntry(String id) async {
    if (_error != null) throw Exception(_error);
    return _entries.firstWhere((e) => e['id'] == id);
  }

  @override
  Future<Map<String, dynamic>> getEnhancedTrends({int days = 30}) async {
    if (_error != null) throw Exception(_error);
    return _trendsResponse ?? {};
  }

  @override
  Future<List<Map<String, dynamic>>> getMoodTrends({int days = 14}) async {
    if (_error != null) throw Exception(_error);
    return _trendsResponse?['moodTrends'] as List<Map<String, dynamic>>? ?? [];
  }

  @override
  Future<void> recordMood({
    required String mood,
    String? emotion,
    String? note,
    String? source,
    double? confidence,
    String? aiSuggestedMood,
    List<Map<String, dynamic>>? aiObservations,
    int? intensity,
  }) async {
    if (_error != null) throw Exception(_error);
    _entries.add({
      'id': 'new_${_entries.length}',
      'mood': mood,
      'emotion': emotion,
      'note': note,
      'source': source ?? 'MANUAL',
      'confidence': confidence,
      'recordedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> deleteMood(String id) async {
    if (_error != null) throw Exception(_error);
    _entries.removeWhere((e) => e['id'] == id);
  }

  @override
  Future<Map<String, dynamic>> getStatistics() async {
    if (_error != null) throw Exception(_error);
    return {
      'totalEntries': _entries.length,
      'entriesThisWeek': _entries.length,
      'currentStreak': 1,
      'longestStreak': 1,
      'mostCommonMood': _entries.isNotEmpty ? _entries.first['mood'] : 'none',
      'averageIntensity': 5.0,
      'moodDistribution': <String, dynamic>{},
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeMood({
    required String mood,
    String? emotion,
    String? note,
    Map<String, dynamic>? cameraObservation,
  }) async {
    if (_error != null) throw Exception(_error);
    return {
      'fusedMood': mood,
      'confidence': 0.85,
      'needsConfirmation': false,
    };
  }
}

void main() {
  // ─── MoodEntry model tests ───
  group('MoodEntry', () {
    test('timeLabel formats 12-hour time correctly', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime(2026, 1, 15, 14, 30),
        moodId: 'happy',
        emotion: 'Grateful',
        note: null,
      );
      expect(entry.timeLabel, '2:30 PM');
    });

    test('timeLabel handles midnight', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime(2026, 1, 15, 0, 0),
        moodId: 'calm',
        emotion: null,
        note: null,
      );
      expect(entry.timeLabel, '12:00 AM');
    });

    test('timeLabel handles noon', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime(2026, 1, 15, 12, 0),
        moodId: 'happy',
        emotion: null,
        note: null,
      );
      expect(entry.timeLabel, '12:00 PM');
    });

    test('dayLabel formats date correctly', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime(2026, 3, 5),
        moodId: 'okay',
        emotion: null,
        note: null,
      );
      expect(entry.dayLabel, '5 Mar');
    });

    test('hasAiData returns false for MANUAL source', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime.now(),
        moodId: 'happy',
        emotion: null,
        note: null,
        source: 'MANUAL',
      );
      expect(entry.hasAiData, isFalse);
    });

    test('hasAiData returns true for CAMERA source', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime.now(),
        moodId: 'happy',
        emotion: null,
        note: null,
        source: 'CAMERA',
      );
      expect(entry.hasAiData, isTrue);
    });

    test('hasAiData returns false when source is null', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime.now(),
        moodId: 'happy',
        emotion: null,
        note: null,
      );
      expect(entry.hasAiData, isFalse);
    });

    test('aiObservations defaults to empty list', () {
      final entry = MoodEntry(
        id: '1',
        date: DateTime.now(),
        moodId: 'happy',
        emotion: null,
        note: null,
      );
      expect(entry.aiObservations, isEmpty);
    });
  });

  // ─── AiObservation model tests ───
  group('AiObservation', () {
    test('fromJson parses all fields', () {
      final json = {
        'source': 'TEXT',
        'emotion': 'happy',
        'confidence': 0.92,
        'sentiment': 'positive',
        'sentimentConfidence': 0.88,
        'suggestedMood': 'happy',
        'modelVersion': '1.0',
      };
      final obs = AiObservation.fromJson(json);
      expect(obs.source, 'TEXT');
      expect(obs.emotion, 'happy');
      expect(obs.confidence, 0.92);
      expect(obs.sentiment, 'positive');
      expect(obs.sentimentConfidence, 0.88);
      expect(obs.suggestedMood, 'happy');
      expect(obs.modelVersion, '1.0');
    });

    test('fromJson handles missing optional fields', () {
      final json = <String, dynamic>{
        'source': 'CAMERA',
        'emotion': 'neutral',
        'confidence': 0.5,
      };
      final obs = AiObservation.fromJson(json);
      expect(obs.source, 'CAMERA');
      expect(obs.emotion, 'neutral');
      expect(obs.confidence, 0.5);
      expect(obs.sentiment, isNull);
      expect(obs.sentimentConfidence, isNull);
      expect(obs.suggestedMood, isNull);
      expect(obs.modelVersion, isNull);
    });

    test('fromJson provides defaults for missing required fields', () {
      final json = <String, dynamic>{};
      final obs = AiObservation.fromJson(json);
      expect(obs.source, '');
      expect(obs.emotion, 'neutral');
      expect(obs.confidence, 0.0);
    });
  });

  // ─── Mood constants tests ───
  group('kMoods', () {
    test('has exactly 6 moods', () {
      expect(kMoods.length, 6);
    });

    test('moodById returns correct mood', () {
      expect(moodById('very_happy').label, 'Great');
      expect(moodById('happy').label, 'Good');
      expect(moodById('calm').label, 'Calm');
      expect(moodById('okay').label, 'Okay');
      expect(moodById('low').label, 'Low');
      expect(moodById('stressed').label, 'Stressed');
    });

    test('moodById falls back to "okay" for unknown id', () {
      final unknown = moodById('unknown_mood');
      expect(unknown.id, 'okay');
    });

    test('mood values range from 1 to 6', () {
      final values = kMoods.map((m) => m.value).toList();
      expect(values, containsAll([1, 2, 4, 5, 6]));
    });

    test('isPositive is true for value >= 5', () {
      expect(moodById('very_happy').isPositive, isTrue);
      expect(moodById('happy').isPositive, isTrue);
      expect(moodById('calm').isPositive, isTrue);
      expect(moodById('okay').isPositive, isFalse);
      expect(moodById('low').isPositive, isFalse);
      expect(moodById('stressed').isPositive, isFalse);
    });

    test('isNegative is true for value <= 2', () {
      expect(moodById('very_happy').isNegative, isFalse);
      expect(moodById('happy').isNegative, isFalse);
      expect(moodById('calm').isNegative, isFalse);
      expect(moodById('okay').isNegative, isFalse);
      expect(moodById('low').isNegative, isTrue);
      expect(moodById('stressed').isNegative, isTrue);
    });
  });

  // ─── MoodController unit tests ───
  group('MoodController', () {
    late StubMoodApi api;
    late MoodController controller;

    setUp(() {
      api = StubMoodApi();
      controller = MoodController(api);
    });

    test('initial state is empty and not loading', () {
      expect(controller.entries, isEmpty);
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
    });

    test('loadEntries populates entries', () async {
      api.setEntries([
        {
          'id': '1',
          'mood': 'happy',
          'emotion': 'Grateful',
          'recordedAt': DateTime.now().toIso8601String(),
        },
      ]);
      await controller.loadEntries();
      expect(controller.entries.length, 1);
      expect(controller.entries.first.moodId, 'happy');
      expect(controller.loading, isFalse);
    });

    test('loadEntries handles errors', () async {
      api.setError('Network error');
      await controller.loadEntries();
      expect(controller.error, isNotNull);
      expect(controller.loading, isFalse);
    });

    test('recordMood adds entry and reloads', () async {
      api.setEntries([]);
      await controller.recordMood(moodId: 'happy', note: 'Test note');
      expect(controller.entries.length, 1);
      expect(controller.entries.first.moodId, 'happy');
    });

    test('deleteMood removes entry and reloads', () async {
      api.setEntries([
        {'id': '1', 'mood': 'happy', 'recordedAt': DateTime.now().toIso8601String()},
      ]);
      await controller.loadEntries();
      expect(controller.entries.length, 1);

      await controller.deleteMood('1');
      expect(controller.entries.length, 0);
    });

    test('analyzeMood returns result on success', () async {
      final result = await controller.analyzeMood(
        mood: 'happy',
        emotion: 'Grateful',
      );
      expect(result, isNotNull);
      expect(result!['fusedMood'], 'happy');
      expect(result['confidence'], 0.85);
    });

    test('analyzeMood returns null on error', () async {
      api.setError('AI service unavailable');
      final result = await controller.analyzeMood(mood: 'happy');
      expect(result, isNull);
      expect(controller.analysisError, isNotNull);
    });

    test('clearAnalysis resets state', () async {
      api.setError('fail');
      await controller.analyzeMood(mood: 'happy');
      expect(controller.analysisError, isNotNull);

      controller.clearAnalysis();
      expect(controller.analysisResult, isNull);
      expect(controller.analysisError, isNull);
    });

    test('loadEntries filters today entries', () async {
      final now = DateTime.now();
      api.setEntries([
        {
          'id': '1',
          'mood': 'happy',
          'recordedAt': DateTime(now.year, now.month, now.day, 10, 0).toIso8601String(),
        },
        {
          'id': '2',
          'mood': 'calm',
          'recordedAt': DateTime(now.year, now.month, now.day - 1, 10, 0).toIso8601String(),
        },
      ]);
      await controller.loadEntries();
      expect(controller.todayEntries.length, 1);
      expect(controller.todayEntries.first.moodId, 'happy');
    });

    test('loadRecentEntries populates recent entries', () async {
      api.setRecent([
        {
          'id': '1',
          'mood': 'happy',
          'recordedAt': DateTime.now().toIso8601String(),
        },
        {
          'id': '2',
          'mood': 'calm',
          'recordedAt': DateTime.now().toIso8601String(),
        },
      ]);
      await controller.loadRecentEntries(limit: 5);
      expect(controller.recentEntries.length, 2);
    });

    test('loadRecentEntries handles errors gracefully', () async {
      api.setError('Network error');
      await controller.loadRecentEntries();
      expect(controller.recentEntries, isEmpty);
    });
  });
}
