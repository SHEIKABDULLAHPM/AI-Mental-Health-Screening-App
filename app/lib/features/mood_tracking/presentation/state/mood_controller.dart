import 'package:flutter/foundation.dart';

import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';

/// Abstract interface for mood-related API calls.
/// Implemented by [FeatureApi] in production; stubbed in tests.
abstract class MoodApi {
  Future<List<Map<String, dynamic>>> getMoodEntries();
  Future<List<Map<String, dynamic>>> getRecentMoodEntries({int limit = 5});
  Future<Map<String, dynamic>> getMoodEntry(String id);
  Future<List<Map<String, dynamic>>> getMoodTrends({int days = 14});
  Future<Map<String, dynamic>> getEnhancedTrends({int days = 30});
  Future<void> recordMood({
    required String mood,
    String? emotion,
    String? note,
    String? source,
    double? confidence,
    String? aiSuggestedMood,
    List<Map<String, dynamic>>? aiObservations,
    int? intensity,
  });
  Future<void> deleteMood(String id);
  Future<Map<String, dynamic>> analyzeMood({
    required String mood,
    String? emotion,
    String? note,
    Map<String, dynamic>? cameraObservation,
  });
  Future<Map<String, dynamic>> getStatistics();
}

/// Manages mood tracking state: entries, today's moods, trends,
/// and multimodal AI analysis.
class MoodController extends ChangeNotifier {
  MoodController(this._api);

  final MoodApi _api;

  List<MoodEntry> _entries = [];
  List<MoodEntry> _todayEntries = [];
  List<MoodEntry> _recentEntries = [];
  List<Map<String, dynamic>> _trends = [];
  Map<String, dynamic>? _enhancedTrends;
  Map<String, dynamic>? _statistics;
  bool _loading = false;
  String? _error;

  // ── AI analysis state ──
  Map<String, dynamic>? _analysisResult;
  bool _analyzing = false;
  String? _analysisError;

  List<MoodEntry> get entries => _entries;
  List<MoodEntry> get todayEntries => _todayEntries;
  List<MoodEntry> get recentEntries => _recentEntries;
  List<Map<String, dynamic>> get trends => _trends;
  Map<String, dynamic>? get enhancedTrends => _enhancedTrends;
  Map<String, dynamic>? get statistics => _statistics;
  bool get loading => _loading;
  String? get error => _error;

  Map<String, dynamic>? get analysisResult => _analysisResult;
  bool get analyzing => _analyzing;
  String? get analysisError => _analysisError;

  // ──────────────────────────────────────────── Loading helpers

  void _start() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void _fail(Object e) {
    _error = _message(e);
    _loading = false;
    notifyListeners();
  }

  String _message(Object e) =>
      e is Failure ? e.message : 'Something went wrong.';

  // ──────────────────────────────────────────── Public methods

  /// Fetch all mood entries for the current user.
  Future<void> loadEntries() async {
    _start();
    try {
      final rows = await _api.getMoodEntries();
      _entries = rows.map(_fromApi).toList();
      _filterToday();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetch recent mood entries for the home screen "Recent moods" section.
  Future<void> loadRecentEntries({int limit = 5}) async {
    try {
      final rows = await _api.getRecentMoodEntries(limit: limit);
      _recentEntries = rows.map(_fromApi).toList();
      notifyListeners();
    } catch (_) {
      // Non-critical: home screen can fall back to filtering `entries`.
    }
  }

  /// Fetch aggregated mood statistics (streaks, averages, distributions).
  Future<void> loadStatistics() async {
    try {
      _statistics = await _api.getStatistics();
      notifyListeners();
    } catch (_) {
      // Non-critical: home screen can show without stats.
    }
  }

  /// Fetch a single mood entry by ID from the API.
  Future<MoodEntry?> loadEntry(String id) async {
    try {
      final json = await _api.getMoodEntry(id);
      return _fromApi(json);
    } catch (e) {
      // Fallback: search local entries
      return _entries.where((e) => e.id == id).firstOrNull;
    }
  }

  void _filterToday() {
    final now = DateTime.now();
    _todayEntries = _entries.where((e) =>
        e.date.year == now.year &&
        e.date.month == now.month &&
        e.date.day == now.day,
    ).toList();
  }

  /// Analyze mood via AI service (text emotion + camera fusion).
  /// Returns the analysis result for the UI to display before confirmation.
  Future<Map<String, dynamic>?> analyzeMood({
    required String mood,
    String? emotion,
    String? note,
    Map<String, dynamic>? cameraObservation,
  }) async {
    _analyzing = true;
    _analysisError = null;
    _analysisResult = null;
    notifyListeners();

    try {
      final result = await _api.analyzeMood(
        mood: mood,
        emotion: emotion,
        note: note,
        cameraObservation: cameraObservation,
      );
      _analysisResult = result;
      _analyzing = false;
      notifyListeners();
      return result;
    } catch (e) {
      _analysisError = _message(e);
      _analyzing = false;
      notifyListeners();
      // Return null on failure — caller can fall back to manual
      return null;
    }
  }

  /// Record a new mood (optionally with AI observations) and reload entries.
  /// [aiObservations] should be a list of maps matching the backend
  /// AiObservationInput schema (source, emotion, confidence, sentiment, etc.).
  Future<void> recordMood({
    required String moodId,
    String? emotion,
    String? note,
    String? source,
    double? confidence,
    String? aiSuggestedMood,
    List<Map<String, dynamic>>? aiObservations,
    int? intensity,
  }) async {
    _start();
    try {
      await _api.recordMood(
        mood: moodId,
        emotion: emotion,
        note: note,
        source: source,
        confidence: confidence,
        aiSuggestedMood: aiSuggestedMood,
        aiObservations: aiObservations,
        intensity: intensity,
      );
      _analysisResult = null;
      await loadEntries();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load aggregated trend data for the mood chart.
  Future<void> loadTrends({int days = 14}) async {
    _start();
    try {
      _trends = await _api.getMoodTrends(days: days);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load enhanced trends with emotion distribution and daily data.
  Future<void> loadEnhancedTrends({int days = 30}) async {
    _start();
    try {
      _enhancedTrends = await _api.getEnhancedTrends(days: days);
      final moodTrends = _enhancedTrends?['moodTrends'];
      _trends = (moodTrends is List)
          ? moodTrends.cast<Map<String, dynamic>>()
          : [];
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Delete a mood entry by id and refresh the list.
  Future<void> deleteMood(String id) async {
    _start();
    try {
      await _api.deleteMood(id);
      await loadEntries();
    } catch (e) {
      _fail(e);
    }
  }

  /// Clear the current analysis result (e.g. when user cancels).
  void clearAnalysis() {
    _analysisResult = null;
    _analysisError = null;
    notifyListeners();
  }
}

// ──────────────────────────────────────────── API → domain mapping

MoodEntry _fromApi(Map<String, dynamic> json) {
  final observations = (json['aiObservations'] as List?)
          ?.map((obs) => AiObservation.fromJson(obs as Map<String, dynamic>))
          .toList() ??
      [];

  return MoodEntry(
    id: json['id'] as String? ?? '',
    date: _parseDate(json['recordedAt']),
    moodId: json['mood'] as String? ?? '',
    emotion: json['emotion'] as String?,
    note: json['note'] as String?,
    source: json['source'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble(),
    analysisStatus: json['analysisStatus'] as String?,
    aiObservations: observations,
    aiSuggestedMood: json['aiSuggestedMood'] as String?,
    intensity: (json['intensity'] as num?)?.toInt(),
  );
}

DateTime _parseDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}
