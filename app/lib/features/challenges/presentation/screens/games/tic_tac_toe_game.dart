import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_result.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_wrapper.dart'
    show GameCompleteExtension;
import 'package:mindease/features/challenges/presentation/screens/games/tic_tac_toe_ai.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// A polished Tic-Tac-Toe game with AI and Two-Player modes.
class TicTacToeGame extends StatefulWidget {
  const TicTacToeGame({super.key, this.onGameComplete});

  final void Function(GameResult result)? onGameComplete;

  @override
  State<TicTacToeGame> createState() => _TicTacToeGameState();
}

enum _Player { x, o, none }

enum _GameState { playing, xWon, oWon, draw }

enum _GameMode { ai, twoPlayer }

enum _Difficulty { easy, medium, hard }

class _TicTacToeGameState extends State<TicTacToeGame>
    with TickerProviderStateMixin {
  late List<List<_Player>> _board;
  _Player _currentPlayer = _Player.x;
  _GameState _gameState = _GameState.playing;
  _GameMode _gameMode = _GameMode.ai;
  _Difficulty _difficulty = _Difficulty.medium;
  bool _aiThinking = false;
  int _xWins = 0;
  int _oWins = 0;
  int _draws = 0;
  int _totalMoves = 0;
  // Guards against stale background-AI callbacks applying moves after a reset.
  int _aiEpoch = 0;
  late AnimationController _winLineController;
  late Animation<double> _winLineAnimation;
  List<Point<int>>? _winLine;

  // Cell placement animation controllers (one per cell, for subtle pop-in).
  late List<AnimationController> _cellPopControllers;
  late List<Animation<double>> _cellPopAnimations;

  @override
  void initState() {
    super.initState();
    _winLineController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _winLineAnimation = CurvedAnimation(
      parent: _winLineController,
      curve: Curves.easeOutCubic,
    );

    _cellPopControllers = List.generate(
      9,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 180),
        vsync: this,
      ),
    );
    _cellPopAnimations = _cellPopControllers
        .map((c) => Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: c, curve: Curves.easeOutBack),
            ),)
        .toList();

    _resetBoard();
  }

  @override
  void dispose() {
    _winLineController.dispose();
    for (final c in _cellPopControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetBoard() {
    _aiEpoch++;
    _board = List.generate(3, (_) => List.filled(3, _Player.none));
    _currentPlayer = _Player.x;
    _gameState = _GameState.playing;
    _aiThinking = false;
    _winLine = null;
    _totalMoves = 0;
    _winLineController.reset();
    for (final c in _cellPopControllers) {
      c.reset();
    }
  }

  void _newGame() {
    setState(() => _resetBoard());
  }

  bool _isAiTurn() =>
      _gameMode == _GameMode.ai && _currentPlayer == _Player.o;

  void _onCellTap(int row, int col) {
    if (_gameState != _GameState.playing) return;
    if (_board[row][col] != _Player.none) return;
    if (_aiThinking) return;

    HapticFeedback.selectionClick();
    _makeMove(row, col);

    // Trigger AI move after player's turn in AI mode. Uses a background
    // isolate so the minimax computation never blocks the UI thread.
    if (_gameState == _GameState.playing && _isAiTurn()) {
      _triggerAiMove();
    }
  }

  void _makeMove(int row, int col) {
    setState(() {
      _board[row][col] = _currentPlayer;
      _totalMoves++;
      _checkGameState();
      if (_gameState == _GameState.playing) {
        _currentPlayer =
            _currentPlayer == _Player.x ? _Player.o : _Player.x;
      }
    });
    // Pop-in animation for the placed cell
    final idx = row * 3 + col;
    _cellPopControllers[idx].forward(from: 0);
  }

  void _checkGameState() {
    // Check rows
    for (int r = 0; r < 3; r++) {
      if (_board[r][0] != _Player.none &&
          _board[r][0] == _board[r][1] &&
          _board[r][1] == _board[r][2]) {
        _gameState = _board[r][0] == _Player.x
            ? _GameState.xWon
            : _GameState.oWon;
        _winLine = [Point(r, 0), Point(r, 1), Point(r, 2)];
        _winLineController.forward();
        _updateScores();
        return;
      }
    }
    // Check columns
    for (int c = 0; c < 3; c++) {
      if (_board[0][c] != _Player.none &&
          _board[0][c] == _board[1][c] &&
          _board[1][c] == _board[2][c]) {
        _gameState = _board[0][c] == _Player.x
            ? _GameState.xWon
            : _GameState.oWon;
        _winLine = [Point(0, c), Point(1, c), Point(2, c)];
        _winLineController.forward();
        _updateScores();
        return;
      }
    }
    // Check diagonals
    if (_board[0][0] != _Player.none &&
        _board[0][0] == _board[1][1] &&
        _board[1][1] == _board[2][2]) {
      _gameState = _board[0][0] == _Player.x
          ? _GameState.xWon
          : _GameState.oWon;
      _winLine = [
        const Point(0, 0),
        const Point(1, 1),
        const Point(2, 2),
      ];
      _winLineController.forward();
      _updateScores();
      return;
    }
    if (_board[0][2] != _Player.none &&
        _board[0][2] == _board[1][1] &&
        _board[1][1] == _board[2][0]) {
      _gameState = _board[0][2] == _Player.x
          ? _GameState.xWon
          : _GameState.oWon;
      _winLine = [
        const Point(0, 2),
        const Point(1, 1),
        const Point(2, 0),
      ];
      _winLineController.forward();
      _updateScores();
      return;
    }
    // Check draw
    bool full = true;
    for (final row in _board) {
      if (row.contains(_Player.none)) {
        full = false;
        break;
      }
    }
    if (full) {
      _gameState = _GameState.draw;
      _updateScores();
    }
  }

  void _updateScores() {
    _aiThinking = false;
    switch (_gameState) {
      case _GameState.xWon:
        _xWins++;
      case _GameState.oWon:
        _oWins++;
      case _GameState.draw:
        _draws++;
      case _GameState.playing:
        break;
    }
    if (_gameState != _GameState.playing) {
      _onGameEnded();
    }
  }

  // ---------- AI Logic ----------

  /// Trigger the AI's turn. Minimax on a 3×3 board runs in <1ms so we
  /// compute it directly — no isolate overhead, no noticeable delay.
  void _triggerAiMove() {
    if (_gameState != _GameState.playing) return;
    final epoch = _aiEpoch;
    _aiThinking = true;

    // Use addPostFrameCallback so the player's marker renders in this
    // frame, then AI moves in the very next frame (instant feel).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _aiEpoch || _gameState != _GameState.playing) {
        _aiThinking = false;
        return;
      }

      Point<int>? move;
      switch (_difficulty) {
        case _Difficulty.easy:
          move = _randomMove();
        case _Difficulty.medium:
          move = Random().nextBool()
              ? _bestMoveSync()
              : _randomMove();
        case _Difficulty.hard:
          move = _bestMoveSync();
      }

      if (!mounted || epoch != _aiEpoch || _gameState != _GameState.playing) {
        _aiThinking = false;
        return;
      }
      final captured = move;
      if (captured != null) {
        final mx = captured.x;
        final my = captured.y;
        HapticFeedback.lightImpact();
        setState(() {
          _board[mx][my] = _currentPlayer;
          _totalMoves++;
          _checkGameState();
          if (_gameState == _GameState.playing) {
            _currentPlayer = _currentPlayer == _Player.x ? _Player.o : _Player.x;
          }
          _aiThinking = false;
        });
        _cellPopControllers[mx * 3 + my].forward(from: 0);
      } else {
        setState(() => _aiThinking = false);
      }
    });
  }

  Point<int>? _randomMove() {
    final empty = <Point<int>>[];
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        if (_board[r][c] == _Player.none) empty.add(Point(r, c));
      }
    }
    if (empty.isEmpty) return null;
    return empty[Random().nextInt(empty.length)];
  }

  /// Runs minimax synchronously. On a 3×3 board this takes <1ms — no
  /// isolate needed.
  Point<int>? _bestMoveSync() {
    final snapshot = _board
        .map((r) => r.map((p) => p.index).toList())
        .toList();
    final result = aiBestMove(snapshot);
    if (result == null) return null;
    return Point(result.$1, result.$2);
  }

  // ---------- Game Result ----------

  void _onGameEnded() {
    final won = _gameState == _GameState.xWon;
    final draw = _gameState == _GameState.draw;

    final score =
        won ? 100 + _totalMoves * 5 : draw ? 50 : 0;

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _showGameResultDialog(score, won, draw);
    });
  }

  void _showGameResultDialog(int score, bool won, bool draw) {
    final theme = Theme.of(context);

    String resultText;
    Color resultColor;
    IconData resultIcon;

    if (_gameMode == _GameMode.twoPlayer) {
      final winner = won ? 'X' : draw ? null : 'O';
      resultText = draw ? 'Draw!' : 'Player $winner wins!';
      resultColor = draw
          ? theme.colorScheme.onSurfaceVariant
          : won
              ? theme.colorScheme.primary
              : theme.colorScheme.error;
      resultIcon =
          draw ? Icons.handshake_rounded : Icons.emoji_events_rounded;
    } else {
      resultText = won ? 'You win!' : draw ? 'Draw!' : 'AI wins!';
      resultColor = won
          ? theme.colorScheme.primary
          : draw
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error;
      resultIcon = won
          ? Icons.emoji_events_rounded
          : draw
              ? Icons.handshake_rounded
              : Icons.psychology_rounded;
    }

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
              '$_totalMoves moves · $score pts',
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
                  score: score,
                  completed: won || draw,
                  moves: _totalMoves,
                  gameType: 'tic_tac_toe',
                  difficulty: _gameMode == _GameMode.ai
                      ? _difficulty.name
                      : 'two_player',
                ),
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenW = MediaQuery.of(context).size.width;
    final boardSize = min(screenW - AppSpacing.lg * 2, 340.0);
    final cellSize = (boardSize - 12) / 3;

    return FeatureScaffold(
      title: 'Tic-Tac-Toe',
      actions: [
        IconButton(
          onPressed: _newGame,
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
          // Mode selector — guarded during AI thinking
          _ModeSelector(
            mode: _gameMode,
            enabled: !_aiThinking,
            onChanged: (mode) {
              HapticFeedback.selectionClick();
              setState(() {
                _gameMode = mode;
                _resetBoard();
              });
            },
          ),
          if (_gameMode == _GameMode.ai) ...[
            const SizedBox(height: AppSpacing.sm),
            // Difficulty indicator
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_difficulty.name[0].toUpperCase()}${_difficulty.name.substring(1)} AI',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Score row
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ScoreItem(
                    label: _gameMode == _GameMode.ai
                        ? 'You (X)'
                        : 'Player X',
                    score: _xWins,
                    color: theme.colorScheme.primary,
                  ),
                  _ScoreItem(
                    label: 'Draws',
                    score: _draws,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  _ScoreItem(
                    label: _gameMode == _GameMode.ai
                        ? 'AI (O)'
                        : 'Player O',
                    score: _oWins,
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Status
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _statusText,
                key: ValueKey(_statusText),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _statusColor(theme),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Board
          Center(
            child: SizedBox(
              width: boardSize,
              height: boardSize,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 9,
                itemBuilder: (context, index) {
                  final r = index ~/ 3;
                  final c = index % 3;
                  return _TicTacCell(
                    player: _board[r][c],
                    cellSize: cellSize,
                    isWinCell:
                        _winLine?.any((p) => p.x == r && p.y == c) ??
                            false,
                    winAnimation: _winLineAnimation,
                    popAnimation: _cellPopAnimations[index],
                    onTap: () => _onCellTap(r, c),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // New game button
          if (_gameState != _GameState.playing)
            Center(
              child: FilledButton.icon(
                onPressed: _newGame,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('New Game'),
              ),
            ),
          // Difficulty picker (AI mode only, during play)
          if (_gameMode == _GameMode.ai &&
              _gameState == _GameState.playing) ...[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: SegmentedButton<_Difficulty>(
                segments: const [
                  ButtonSegment(
                      value: _Difficulty.easy,
                      label: Text('Easy'),
                  ),
                  ButtonSegment(
                      value: _Difficulty.medium,
                      label: Text('Medium'),
                  ),
                  ButtonSegment(
                      value: _Difficulty.hard,
                      label: Text('Hard'),
                  ),
                ],
                selected: {_difficulty},
                onSelectionChanged: (sel) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _difficulty = sel.first;
                    _resetBoard();
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _statusText {
    if (_gameMode == _GameMode.twoPlayer) {
      return switch (_gameState) {
        _GameState.playing => _currentPlayer == _Player.x
            ? "Player X's turn"
            : "Player O's turn",
        _GameState.xWon => 'Player X wins!',
        _GameState.oWon => 'Player O wins!',
        _GameState.draw => 'Draw!',
      };
    }
    return switch (_gameState) {
      _GameState.playing =>
        _aiThinking ? 'AI thinking...' : 'Your turn (X)',
      _GameState.xWon => 'You win!',
      _GameState.oWon => 'AI wins!',
      _GameState.draw => 'Draw!',
    };
  }

  Color _statusColor(ThemeData theme) {
    return switch (_gameState) {
      _GameState.playing => theme.colorScheme.onSurface,
      _GameState.xWon => theme.colorScheme.primary,
      _GameState.oWon => theme.colorScheme.error,
      _GameState.draw => theme.colorScheme.onSurfaceVariant,
    };
  }
}

// ---------------------------------------------------------------------------
// Mode selector
// ---------------------------------------------------------------------------

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.onChanged,
    this.enabled = true,
  });

  final _GameMode mode;
  final ValueChanged<_GameMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius:
                BorderRadius.circular(AppSpacing.radiusMd),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _ModeChip(
                  icon: Icons.smart_toy_rounded,
                  label: 'vs AI',
                  selected: mode == _GameMode.ai,
                  onTap: () => onChanged(_GameMode.ai),
                ),
              ),
              Expanded(
                child: _ModeChip(
                  icon: Icons.people_rounded,
                  label: 'Two Players',
                  selected: mode == _GameMode.twoPlayer,
                  onTap: () => onChanged(_GameMode.twoPlayer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color:
              selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius:
              BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score item
// ---------------------------------------------------------------------------

class _ScoreItem extends StatelessWidget {
  const _ScoreItem({
    required this.label,
    required this.score,
    required this.color,
  });

  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Game cell
// ---------------------------------------------------------------------------

class _TicTacCell extends StatelessWidget {
  const _TicTacCell({
    required this.player,
    required this.cellSize,
    required this.isWinCell,
    required this.winAnimation,
    required this.popAnimation,
    required this.onTap,
  });

  final _Player player;
  final double cellSize;
  final bool isWinCell;
  final Animation<double> winAnimation;
  final Animation<double> popAnimation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color? bgColor;
    if (isWinCell && player != _Player.none) {
      bgColor =
          theme.colorScheme.tertiary.withValues(alpha: 0.15);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([winAnimation, popAnimation]),
        builder: (context, child) {
          final glow = isWinCell ? winAnimation.value : 0.0;
          final scale = player != _Player.none
              ? 0.8 + popAnimation.value * 0.2
              : 1.0;
          return Container(
            decoration: BoxDecoration(
              color: bgColor ?? theme.colorScheme.surface,
              borderRadius:
                  BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: isWinCell && player != _Player.none
                    ? theme.colorScheme.tertiary.withValues(
                        alpha: 0.4 + glow * 0.4,
                    )
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
                width: isWinCell ? 2.0 : 1.0,
              ),
            ),
            child: Center(
              child: Transform.scale(
                scale: scale,
                child: _buildSymbol(theme),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget? _buildSymbol(ThemeData theme) {
    switch (player) {
      case _Player.x:
        return Icon(
          Icons.close_rounded,
          size: cellSize * 0.5,
          color: theme.colorScheme.primary,
        );
      case _Player.o:
        return Icon(
          Icons.circle_outlined,
          size: cellSize * 0.5,
          color: theme.colorScheme.error,
        );
      case _Player.none:
        return null;
    }
  }
}
