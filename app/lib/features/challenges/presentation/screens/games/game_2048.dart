import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_result.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_wrapper.dart'
    show GameCompleteExtension;
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Colors for tile values, keyed by numeric value.
const Map<int, Color> _kTileColors = {
  0: Color(0xFFCDC1B4),
  2: Color(0xFFEEE4DA),
  4: Color(0xFFEDE0C8),
  8: Color(0xFFF2B179),
  16: Color(0xFFF59563),
  32: Color(0xFFF67C5F),
  64: Color(0xFFF65E3B),
  128: Color(0xFFEDCF72),
  256: Color(0xFFEDCC61),
  512: Color(0xFFEDC850),
  1024: Color(0xFFEDC53F),
  2048: Color(0xFFEDC22E),
};

/// A clean 2048 game adapted for the Mindease challenges feature.
///
/// Swipe to slide numbered tiles on a 4×4 grid. Tiles with the same value
/// merge when they collide, and a new tile appears after each move. The goal
/// is to create a tile with the value 2048.
class Game2048 extends StatefulWidget {
  const Game2048({super.key, this.onGameComplete});

  final void Function(GameResult result)? onGameComplete;

  @override
  State<Game2048> createState() => _Game2048State();
}

class _Game2048State extends State<Game2048> {
  late List<List<int>> _grid;
  int _score = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  bool _won = false;
  bool _resultShown = false;
  int _moveCount = 0;

  // Debounce: prevent rapid-fire swipes from corrupting board state.
  bool _moving = false;
  static const Duration _moveDelay = Duration(milliseconds: 50);

  // Track which cells just merged for animation.
  late Set<int> _mergedCells;

  // Minimum swipe distance (logical pixels) to count as a swipe.
  static const double _minSwipeDistance = 20;

  @override
  void initState() {
    super.initState();
    _mergedCells = {};
    _initGrid();
  }

  void _initGrid() {
    _grid = List.generate(4, (_) => List.filled(4, 0));
    _score = 0;
    _gameOver = false;
    _won = false;
    _resultShown = false;
    _moveCount = 0;
    _mergedCells = {};
    _addRandomTile();
    _addRandomTile();
  }

  void _addRandomTile() {
    final empty = <Point<int>>[];
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        if (_grid[r][c] == 0) empty.add(Point(r, c));
      }
    }
    if (empty.isEmpty) return;
    final rng = Random();
    final cell = empty[rng.nextInt(empty.length)];
    _grid[cell.x][cell.y] = rng.nextDouble() < 0.9 ? 2 : 4;
  }

  /// Returns true if any move was made.
  bool _move(_Direction dir) {
    if (_gameOver) return false;

    bool moved = false;
    final oldGrid = _grid.map((r) => List<int>.from(r)).toList();
    _mergedCells.clear();

    switch (dir) {
      case _Direction.left:
        for (int r = 0; r < 4; r++) {
          final row = _grid[r].where((v) => v != 0).toList();
          final merged = _merge(row);
          _grid[r] = merged + List.filled(4 - merged.length, 0);
          // Track merged cells
          for (int i = 0; i < merged.length; i++) {
            if (i + 1 < merged.length && merged[i] == merged[i + 1]) {
              // This pair merged at position i in the original row
            }
            if (merged[i] > (oldGrid[r].where((v) => v != 0).toList().elementAtOrNull(i) ?? 0)) {
              _mergedCells.add(r * 4 + i);
            }
          }
        }
      case _Direction.right:
        for (int r = 0; r < 4; r++) {
          final row = _grid[r].reversed.where((v) => v != 0).toList();
          final merged = _merge(row);
          _grid[r] =
              List.filled(4 - merged.length, 0) + merged.reversed.toList();
        }
      case _Direction.up:
        for (int c = 0; c < 4; c++) {
          final col = [for (int r = 0; r < 4; r++) _grid[r][c]]
              .where((v) => v != 0)
              .toList();
          final merged = _merge(col);
          for (int r = 0; r < 4; r++) {
            _grid[r][c] = r < merged.length ? merged[r] : 0;
          }
        }
      case _Direction.down:
        for (int c = 0; c < 4; c++) {
          final col = [for (int r = 0; r < 4; r++) _grid[r][c]]
              .reversed
              .where((v) => v != 0)
              .toList();
          final merged = _merge(col);
          for (int r = 0; r < 4; r++) {
            _grid[r][c] =
                r < 4 - merged.length ? 0 : merged[3 - r];
          }
        }
    }

    // Check if grid changed
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        if (_grid[r][c] != oldGrid[r][c]) moved = true;
      }
    }

    if (moved) {
      _moveCount++;
      _addRandomTile();

      // Track best score continuously.
      if (_score > _bestScore) {
        _bestScore = _score;
      }

      // Check for 2048 win
      if (!_won) {
        for (final row in _grid) {
          if (row.contains(2048)) {
            _won = true;
            break;
          }
        }
      }

      // Check game over
      if (!_gameOver && !_canMove()) {
        _gameOver = true;
      }
    }

    return moved;
  }

  /// Merge adjacent equal tiles (left-aligned).
  List<int> _merge(List<int> tiles) {
    final result = <int>[];
    int i = 0;
    while (i < tiles.length) {
      if (i + 1 < tiles.length && tiles[i] == tiles[i + 1]) {
        final merged = tiles[i] * 2;
        result.add(merged);
        _score += merged;
        i += 2;
      } else {
        result.add(tiles[i]);
        i++;
      }
    }
    return result;
  }

  bool _canMove() {
    // Any empty cell?
    for (final row in _grid) {
      if (row.contains(0)) return true;
    }
    // Any adjacent equal tiles?
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        final v = _grid[r][c];
        if (c + 1 < 4 && _grid[r][c + 1] == v) return true;
        if (r + 1 < 4 && _grid[r + 1][c] == v) return true;
      }
    }
    return false;
  }

  void _handleSwipe(_Direction dir) {
    if (_gameOver) return;
    if (_moving) return; // Debounce rapid swipes
    HapticFeedback.selectionClick();
    _moving = true;
    final moved = _move(dir);
    setState(() {});
    if (moved) {
      // Show result dialog once when the game ends or 2048 is reached.
      if ((_gameOver || _won) && !_resultShown) {
        _resultShown = true;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _showGameResultDialog();
        });
      }
    }
    // Release debounce after a short delay
    Future.delayed(_moveDelay, () {
      if (mounted) _moving = false;
    });
  }

  void _resetGame() {
    setState(() => _initGrid());
  }

  void _showGameResultDialog() {
    final theme = Theme.of(context);
    final resultText = _won ? 'You reached 2048!' : 'No more moves!';
    final resultColor =
        _won ? theme.colorScheme.tertiary : theme.colorScheme.error;
    final resultIcon = _won
        ? Icons.emoji_events_rounded
        : Icons.sentiment_dissatisfied_rounded;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: resultColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(resultIcon, size: 36, color: resultColor),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              resultText,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: resultColor,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Score: $_score · $_moveCount moves',
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
              context.completeGame(
                GameResult(
                  score: _score,
                  completed: _won,
                  moves: _moveCount,
                  gameType: '2048',
                  difficulty: _won ? 'completed' : 'in_progress',
                ),
              );
            },
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenW = MediaQuery.of(context).size.width;
    final boardSize = min(screenW - AppSpacing.lg * 2, 380.0);
    // 8px padding on each side + 8px gaps between cells (3 gaps × 8 = 24)
    const gap = 8.0;
    const padding = 8.0;
    final cellSize = (boardSize - padding * 2 - gap * 3) / 4;

    return FeatureScaffold(
      title: '2048',
      actions: [
        IconButton(
          onPressed: _resetGame,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'New game',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          // Score row
          Row(
            children: [
              Expanded(
                child: _ScoreBox(
                  label: 'SCORE',
                  value: '$_score',
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ScoreBox(
                  label: 'BEST',
                  value: '$_bestScore',
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Board
          Center(
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < _minSwipeDistance) return;
                if (v > 0) {
                  _handleSwipe(_Direction.right);
                } else {
                  _handleSwipe(_Direction.left);
                }
              },
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < _minSwipeDistance) return;
                if (v > 0) {
                  _handleSwipe(_Direction.down);
                } else {
                  _handleSwipe(_Direction.up);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  children: [
                    for (int r = 0; r < 4; r++)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: gap),
                        child: Row(
                          children: [
                            for (int c = 0; c < 4; c++)
                              Padding(
                                padding: EdgeInsets.only(
                                    right: c < 3 ? gap : 0,
                                ),
                                child: _TileCell(
                                  value: _grid[r][c],
                                  size: cellSize,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Game status hint
          if (!_gameOver && !_won)
            Center(
              child: Text(
                'Swipe to move tiles',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (_gameOver && !_won)
            Center(
              child: TextButton.icon(
                onPressed: _resetGame,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Play Again'),
              ),
            )
          else if (_won)
            Center(
              child: TextButton.icon(
                onPressed: _showGameResultDialog,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('View Result'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Direction enum
// ---------------------------------------------------------------------------

enum _Direction { up, down, left, right }

// ---------------------------------------------------------------------------
// Score box
// ---------------------------------------------------------------------------

class _ScoreBox extends StatelessWidget {
  const _ScoreBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile cell
// ---------------------------------------------------------------------------

class _TileCell extends StatelessWidget {
  const _TileCell({required this.value, required this.size});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tileColor = _kTileColors[value] ?? const Color(0xFFEDC22E);

    // Light tiles (2, 4) get dark text; all others get white.
    const darkText = Color(0xFF5E4A3A);
    final textColor = (value == 2 || value == 4) ? darkText : Colors.white;

    final fontSize = value >= 1024
        ? size * 0.28
        : value >= 128
            ? size * 0.32
            : size * 0.38;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value == 0
            ? tileColor.withValues(alpha: 0.35)
            : tileColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Center(
        child: value == 0
            ? null
            : Text(
                '$value',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
      ),
    );
  }
}
