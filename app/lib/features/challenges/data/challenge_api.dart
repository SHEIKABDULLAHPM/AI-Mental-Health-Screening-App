/// Abstract interface for challenge-related API calls.
/// Implemented by [FeatureApi] in production; stubbed in tests.
abstract class ChallengeApi {
  Future<Map<String, dynamic>> getChallengeHome();
  Future<List<Map<String, dynamic>>> getAvailableChallenges();
  Future<Map<String, dynamic>> getChallenge(String id);
  Future<Map<String, dynamic>> startChallenge(String id);
  Future<List<Map<String, dynamic>>> getBadges();
  Future<List<Map<String, dynamic>>> getChallengeHistory({int page = 0, int size = 20});
  Future<List<Map<String, dynamic>>> getActiveProgress();
  Future<Map<String, dynamic>> submitGameResult({
    required String challengeId,
    required String gameType,
    required int score,
    required bool completed,
    int moves = 0,
    int durationSeconds = 0,
    String? difficulty,
  });
  Future<Map<String, dynamic>> submitProgress({
    required String challengeId,
    required String sourceRecordId,
  });
}
