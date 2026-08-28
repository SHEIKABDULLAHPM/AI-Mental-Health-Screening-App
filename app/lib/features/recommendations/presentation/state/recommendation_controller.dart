import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/recommendations/data/recommendation.dart';

/// Manages wellness recommendations: listing, detail, feedback, interactions.
class RecommendationController extends ChangeNotifier {
  RecommendationController(this._api);

  final FeatureApi _api;

  List<Recommendation> _recommendations = [];
  Recommendation? _currentRecommendation;
  bool _loading = false;
  String? _error;

  List<Recommendation> get recommendations => _recommendations;
  Recommendation? get currentRecommendation => _currentRecommendation;
  bool get loading => _loading;
  String? get error => _error;

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

  /// Fetch all personalized recommendations for the current user.
  Future<void> loadRecommendations() async {
    _start();
    try {
      final rows = await _api.getRecommendations();
      _recommendations = rows.map(Recommendation.fromJson).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load a single recommendation into [currentRecommendation].
  Future<void> loadById(String id) async {
    _start();
    try {
      final json = await _api.getRecommendation(id);
      _currentRecommendation = Recommendation.fromJson(json);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Refresh the recommendation list (pull-to-refresh).
  Future<void> refresh() => loadRecommendations();

  /// Filter the already-loaded list by [category]. If null, reloads all.
  Future<void> filterByCategory(RecommendationCategory? category) async {
    _start();
    try {
      if (category == null) {
        await loadRecommendations();
        return;
      }
      final rows = await _api.getRecommendationsByCategory(category.name);
      _recommendations = rows.map(Recommendation.fromJson).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Record user feedback on a recommendation.
  /// Types: HELPFUL, NOT_USEFUL, ALREADY_COMPLETED, DISMISSED
  Future<void> recordFeedback(String contentId, String feedbackType) async {
    try {
      await _api.recordRecommendationFeedback(contentId, feedbackType);
    } catch (e) {
      // Feedback failure is non-blocking
    }
  }

  /// Record a user interaction event.
  /// Types: SHOWN, OPENED, STARTED, COMPLETED
  Future<void> recordInteraction(String contentId, String interactionType) async {
    try {
      await _api.recordRecommendationInteraction(contentId, interactionType);
    } catch (e) {
      // Interaction failure is non-blocking
    }
  }
}
