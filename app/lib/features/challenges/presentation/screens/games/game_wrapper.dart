import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_result.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';

/// Wraps a game screen with challenge-system integration.
///
/// When the game completes, this widget submits the result to the backend
/// and navigates to the challenge result screen.
class GameChallengeWrapper extends StatefulWidget {
  const GameChallengeWrapper({
    super.key,
    required this.child,
    this.challengeId,
  });

  final Widget child;
  final String? challengeId;

  @override
  State<GameChallengeWrapper> createState() => _GameChallengeWrapperState();
}

class _GameChallengeWrapperState extends State<GameChallengeWrapper> {
  bool _submitting = false;

  Future<void> _onGameComplete(GameResult result) async {
    if (_submitting) return;
    if (!mounted) return;

    final challengeId = widget.challengeId;

    if (challengeId == null || challengeId.isEmpty) {
      // No active challenge — navigate back with a simple result
      _showResultDialog(result);
      return;
    }

    setState(() => _submitting = true);

    try {
      final ctrl = context.read<ChallengeController>();
      final challenge = await ctrl.submitGameResult(
        challengeId: challengeId,
        gameType: result.gameType,
        score: result.score,
        completed: result.completed,
        moves: result.moves,
        durationSeconds: result.durationSeconds,
        difficulty: result.difficulty,
      );

      if (!mounted) return;

      if (challenge != null) {
        context.pushReplacement(
          '/challenges/$challengeId/result',
          extra: {
            'title': challenge.title,
            'points': challenge.points,
            'badge': challenge.reward,
            'streak': challenge.streak,
            'message': result.completed
                ? 'Great job! You scored ${result.score} points.'
                : 'Game completed — keep going to finish the challenge!',
          },
        );
      } else {
        _showResultDialog(result);
      }
    } catch (_) {
      if (mounted) {
        _showResultDialog(result);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showResultDialog(GameResult result) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              result.completed ? Icons.check_circle_rounded : Icons.sports_esports_rounded,
              size: 48,
              color: result.completed ? theme.colorScheme.tertiary : theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              result.completed ? 'Well Done!' : 'Game Complete',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Score: ${result.score}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/challenges');
            },
            child: const Text('Back to Challenges'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _GameCompletionScope(
      onComplete: _onGameComplete,
      child: Stack(
        children: [
          widget.child,
          if (_submitting)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: AppSpacing.md),
                        Text('Submitting result...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// InheritedWidget to pass the game completion callback down the tree.
class _GameCompletionScope extends InheritedWidget {
  const _GameCompletionScope({
    required super.child,
    required this.onComplete,
  });

  final void Function(GameResult result) onComplete;

  static void complete(BuildContext context, GameResult result) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GameCompletionScope>();
    scope?.onComplete(result);
  }

  @override
  bool updateShouldNotify(_GameCompletionScope oldWidget) =>
      onComplete != oldWidget.onComplete;
}

/// Extension to make it easy for game screens to submit results.
extension GameCompleteExtension on BuildContext {
  void completeGame(GameResult result) {
    _GameCompletionScope.complete(this, result);
  }
}
