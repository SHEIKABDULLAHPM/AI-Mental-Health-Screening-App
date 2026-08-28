import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';

/// Manages the Progress screen state by fetching real-time progress data
/// from the backend ProgressService. All data is computed from actual
/// MongoDB collections — no static or fabricated values.
class ProgressController extends ChangeNotifier {
  ProgressController(this._api);

  final FeatureApi _api;

  Map<String, dynamic>? _progress;
  bool _loading = false;
  String? _error;

  bool get loading => _loading;
  String? get error => _error;
  Map<String, dynamic>? get progress => _progress;

  // ── Wellness ──

  int? get wellnessScore =>
      (_progress?['wellnessScore'] as num?)?.toInt();

  String get wellnessScoreLabel =>
      _progress?['wellnessScoreLabel'] as String? ?? '';

  String get wellnessTrend =>
      _progress?['wellnessTrend'] as String? ?? 'unknown';

  // ── Mood ──

  Map<String, dynamic>? get mood => _progress?['mood'] as Map<String, dynamic>?;

  int get moodTotalEntries =>
      (mood?['totalEntries'] as num?)?.toInt() ?? 0;

  int get moodEntriesThisWeek =>
      (mood?['entriesThisWeek'] as num?)?.toInt() ?? 0;

  int get moodCurrentStreak =>
      (mood?['currentStreak'] as num?)?.toInt() ?? 0;

  int get moodLongestStreak =>
      (mood?['longestStreak'] as num?)?.toInt() ?? 0;

  String? get moodDominant => mood?['dominantMood'] as String?;

  String get moodTrend => mood?['moodTrend'] as String? ?? 'unknown';

  String get moodTrendDescription =>
      mood?['moodTrendDescription'] as String? ?? '';

  Map<String, dynamic> get moodDistribution =>
      (mood?['distribution'] as Map<String, dynamic>?) ?? {};

  bool get moodHasData => mood?['hasData'] as bool? ?? false;

  // ── Journal ──

  Map<String, dynamic>? get journal =>
      _progress?['journal'] as Map<String, dynamic>?;

  int get journalTotalEntries =>
      (journal?['totalEntries'] as num?)?.toInt() ?? 0;

  int get journalEntriesThisWeek =>
      (journal?['entriesThisWeek'] as num?)?.toInt() ?? 0;

  String get journalActivityLevel =>
      journal?['activityLevel'] as String? ?? 'inactive';

  List<String> get journalRecentEmotions {
    final raw = journal?['recentEmotions'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  bool get journalHasData => journal?['hasData'] as bool? ?? false;

  // ── Activities ──

  Map<String, dynamic>? get activities =>
      _progress?['activities'] as Map<String, dynamic>?;

  int get activitiesCompletedThisWeek =>
      (activities?['completedThisWeek'] as num?)?.toInt() ?? 0;

  int get activitiesTotalCompleted =>
      (activities?['totalCompleted'] as num?)?.toInt() ?? 0;

  int get activitiesHelpfulCount =>
      (activities?['helpfulCount'] as num?)?.toInt() ?? 0;

  int get activitiesDismissedCount =>
      (activities?['dismissedCount'] as num?)?.toInt() ?? 0;

  bool get activitiesHasData => activities?['hasData'] as bool? ?? false;

  // ── Engagement ──

  Map<String, dynamic>? get engagement =>
      _progress?['engagement'] as Map<String, dynamic>?;

  int get engagementFeaturesUsed =>
      (engagement?['totalFeaturesUsed'] as num?)?.toInt() ?? 0;

  int get engagementActiveFeatures =>
      (engagement?['activeFeaturesThisWeek'] as num?)?.toInt() ?? 0;

  int get engagementCoachConversations =>
      (engagement?['coachConversations'] as num?)?.toInt() ?? 0;

  String get engagementConsistencyLevel =>
      engagement?['consistencyLevel'] as String? ?? 'inactive';

  String get engagementSummary =>
      engagement?['engagementSummary'] as String? ?? '';

  // ── Insights ──

  List<Map<String, dynamic>> get insights {
    final raw = _progress?['insights'];
    if (raw is List) return raw.cast<Map<String, dynamic>>();
    return [];
  }

  // ── Data availability ──

  String get dataAvailability =>
      _progress?['dataAvailability'] as String? ?? 'insufficient';

  // ── Loading helpers ──

  void _start() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  // ── Public methods ──

  /// Fetch the complete progress summary from the backend.
  Future<void> loadProgress() async {
    _start();
    try {
      _progress = await _api.getProgress();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Refresh progress data.
  Future<void> refresh() => loadProgress();
}
