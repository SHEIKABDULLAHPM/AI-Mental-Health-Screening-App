/// Result of a completed game session, used to submit scores to the challenge
/// system and navigate to the result screen.
class GameResult {
  const GameResult({
    required this.score,
    required this.completed,
    this.moves = 0,
    this.durationSeconds = 0,
    this.difficulty,
    this.gameType = '',
  });

  final int score;
  final bool completed;
  final int moves;
  final int durationSeconds;
  final String? difficulty;
  final String gameType;
}
