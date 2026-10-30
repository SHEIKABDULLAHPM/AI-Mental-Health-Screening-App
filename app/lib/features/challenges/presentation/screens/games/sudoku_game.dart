import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/screens/games/sudoku_generator.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_result.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_wrapper.dart'
    show GameCompleteExtension;
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// A clean, polished Sudoku game for the challenges feature.
///
/// Users fill a 9×9 grid with digits 1–9 so that each row, column, and
/// 3×3 box contains all digits exactly once. Highlights related cells and
/// validates moves in real time.
class SudokuGame extends StatefulWidget {
  const SudokuGame({super.key, this.onGameComplete});

  final void Function(GameResult result)? onGameComplete;

  @override
  State<SudokuGame> createState() => _SudokuGameState();
}

class _SudokuGameState extends State<SudokuGame> {
  List<int> _solution = [];
  late List<int> _userGrid;
  late List<bool> _isOriginal; // cells that came with the puzzle
  late List<Set<int>> _notes; // candidate "pencil" marks per cell
  int _selectedCell = -1;
  SudokuDifficulty _difficulty = SudokuDifficulty.medium;
  int _errors = 0;
  int _hintsUsed = 0;
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _gameStarted = false;
  bool _gameComplete = false;
  bool _pencilMode = false;
  final List<_SudokuSnapshot> _undoStack = [];
  static const int _maxUndo = 100;

  @override
  void initState() {
    super.initState();
    _createPuzzle();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _createPuzzle() {
    _timer?.cancel();
    final gen = SudokuGenerator(difficulty: _difficulty);
    final (puzzle, solution) = gen.generate();
    _solution = solution;
    _userGrid = List<int>.from(puzzle);
    _isOriginal = puzzle.map((v) => v != 0).toList();
    _notes = List.generate(81, (_) => <int>{});
    _selectedCell = -1;
    _errors = 0;
    _hintsUsed = 0;
    _elapsedSeconds = 0;
    _gameStarted = false;
    _gameComplete = false;
    _pencilMode = false;
    _undoStack.clear();
    if (mounted) setState(() {});
  }

  void _startTimer() {
    if (_gameStarted) return;
    if (_gameComplete) return;
    _gameStarted = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  /// Records the current board so it can be restored by [undo].
  void _pushUndo() {
    final snapshot = _SudokuSnapshot(
      grid: List<int>.from(_userGrid),
      notes: [for (final s in _notes) Set<int>.from(s)],
      selected: _selectedCell,
      errors: _errors,
      hints: _hintsUsed,
    );
    _undoStack.add(snapshot);
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_gameComplete) return;
    if (_undoStack.isEmpty) return;
    final s = _undoStack.removeLast();
    _userGrid = List<int>.from(s.grid);
    _notes = [for (final n in s.notes) Set<int>.from(n)];
    _selectedCell = s.selected;
    _errors = s.errors;
    _hintsUsed = s.hints;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  /// Clears all user progress but keeps the same puzzle.
  void _resetBoard() {
    if (_gameComplete) return;
    _pushUndo();
    setState(() {
      for (int i = 0; i < 81; i++) {
        if (!_isOriginal[i]) {
          _userGrid[i] = 0;
          _notes[i] = <int>{};
        }
      }
      _errors = 0;
      _hintsUsed = 0;
      _selectedCell = -1;
    });
  }

  void _onCellTap(int index) {
    if (_gameComplete) return;
    _startTimer();
    HapticFeedback.selectionClick();
    setState(() => _selectedCell = index);
  }

  void _togglePencilMode() {
    if (_gameComplete) return;
    HapticFeedback.selectionClick();
    setState(() => _pencilMode = !_pencilMode);
  }

  void _onNumberInput(int num) {
    if (_selectedCell < 0 || _isOriginal[_selectedCell]) return;
    if (_gameComplete) return;
    _startTimer();
    _pushUndo();

    if (_pencilMode) {
      // Toggle a note on the selected editable cell. Only allowed if it
      // is empty.
      if (_userGrid[_selectedCell] == 0) {
        setState(() {
          final notes = _notes[_selectedCell];
          if (!notes.add(num)) {
            notes.remove(num);
          }
        });
      } else {
        // Value is present: ignore note toggling on a filled cell.
        if (_undoStack.isNotEmpty) _undoStack.removeLast();
      }
      return;
    }

    final prev = _userGrid[_selectedCell];
    if (prev == num) {
      // Tapping the same number erases it
      setState(() {
        _userGrid[_selectedCell] = 0;
        _notes[_selectedCell] = <int>{};
      });
      return;
    }
    setState(() {
      _userGrid[_selectedCell] = num;
      // Entering a value clears any pencil marks on that cell.
      _notes[_selectedCell] = <int>{};

      if (num != 0 && num != _solution[_selectedCell]) {
        _errors++;
        HapticFeedback.heavyImpact();
      }

      _checkCompletion();
    });
  }

  void _onErase() {
    if (_selectedCell < 0 || _isOriginal[_selectedCell]) return;
    if (_gameComplete) return;
    _startTimer();
    _pushUndo();
    setState(() {
      if (_pencilMode) {
        _notes[_selectedCell] = <int>{};
      } else {
        _userGrid[_selectedCell] = 0;
        _notes[_selectedCell] = <int>{};
      }
    });
  }

  void _onHint() {
    if (_gameComplete) return;
    _startTimer();
    _pushUndo();

    // Find an empty or wrong cell and fill it with the correct value
    final rng = Random();
    final candidates = <int>[];
    for (int i = 0; i < 81; i++) {
      if (!_isOriginal[i] && _userGrid[i] != _solution[i]) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) {
      if (_undoStack.isNotEmpty) _undoStack.removeLast();
      return;
    }

    final idx = candidates[rng.nextInt(candidates.length)];
    HapticFeedback.heavyImpact();
    setState(() {
      _userGrid[idx] = _solution[idx];
      _notes[idx] = <int>{};
      _isOriginal[idx] = true;
      _hintsUsed++;
      _selectedCell = idx;
      _checkCompletion();
    });
  }

  void _checkCompletion() {
    for (int i = 0; i < 81; i++) {
      if (_userGrid[i] != _solution[i]) {
        return;
      }
    }
    _gameComplete = true;
    _timer?.cancel();
    _showCompletionDialog();
  }

  /// Renders pencil notes as a 3×3 mini-grid inside an empty cell.
  Widget? _buildNotes(ThemeData theme, int index, double cellSize) {
    final notes = _notes[index];
    if (notes.isEmpty) return null;

    final noteSize = cellSize / 3;
    final noteFont = noteSize * 0.6;

    return Padding(
      padding: EdgeInsets.all(noteSize * 0.1),
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (var d = 1; d <= 9; d++)
            Center(
              child: Text(
                '$d',
                style: TextStyle(
                  fontSize: noteFont,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: notes.contains(d)
                      ? theme.colorScheme.onSurfaceVariant
                      : Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    final theme = Theme.of(context);
    final score = max(
            100,
            500 -
                _errors * 30 -
                _hintsUsed * 50 -
                (_elapsedSeconds ~/ 10) * 5,
        )
        .clamp(0, 500);

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
                color: theme.colorScheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 36,
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Puzzle Complete!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${_difficulty.displayName} · ${_formatTime(_elapsedSeconds)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Errors: $_errors · Hints: $_hintsUsed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$score points',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
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
                  completed: true,
                  moves: _errors,
                  durationSeconds: _elapsedSeconds,
                  gameType: 'sudoku',
                  difficulty: _difficulty.name,
                ),
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenW = MediaQuery.of(context).size.width;
    final gridSize = min(screenW - AppSpacing.lg * 2, 380.0);
    final cellSize = (gridSize - 10 * 1.5) / 9;

    final selectedRow = _selectedCell >= 0 ? _selectedCell ~/ 9 : -1;
    final selectedCol = _selectedCell >= 0 ? _selectedCell % 9 : -1;
    final selectedBox = _selectedCell >= 0
        ? (selectedRow ~/ 3) * 3 + (selectedCol ~/ 3)
        : -1;
    final selectedValue =
        _selectedCell >= 0 ? _userGrid[_selectedCell] : 0;

    return FeatureScaffold(
      title: 'Sudoku',
      actions: [
        IconButton(
          onPressed: _createPuzzle,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'New puzzle',
        ),
        PopupMenuButton<SudokuDifficulty>(
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Difficulty',
          onSelected: (d) {
            HapticFeedback.selectionClick();
            setState(() {
              _difficulty = d;
              _createPuzzle();
            });
          },
          itemBuilder: (context) => SudokuDifficulty.values
              .map((d) => PopupMenuItem(
                    value: d,
                    child: Text(d.displayName),
                ),)
              .toList(),
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
          // Status bar
          _StatusBar(
            errors: _errors,
            hints: _hintsUsed,
            time: _formatTime(_elapsedSeconds),
            difficulty: _difficulty,
          ),
          const SizedBox(height: AppSpacing.md),
          // Sudoku grid
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.outline.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SizedBox(
                width: gridSize,
                height: gridSize,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 9,
                    crossAxisSpacing: 1.5,
                    mainAxisSpacing: 1.5,
                  ),
                  itemCount: 81,
                  itemBuilder: (context, index) {
                    final row = index ~/ 9;
                    final col = index % 9;
                    final value = _userGrid[index];
                    final isOrig = _isOriginal[index];
                    final isSelected = index == _selectedCell;
                    final isInSameRow = row == selectedRow;
                    final isInSameCol = col == selectedCol;
                    final isInSameBox =
                        (row ~/ 3) * 3 + (col ~/ 3) == selectedBox;
                    final isRelated = (isInSameRow ||
                            isInSameCol ||
                            isInSameBox) &&
                        _selectedCell >= 0;
                    final isSameValue = value != 0 &&
                        value == selectedValue &&
                        !isSelected;

                    // Thicker borders for 3×3 boxes
                    final rightBorder =
                        (col + 1) % 3 == 0 && col < 8;
                    final bottomBorder =
                        (row + 1) % 3 == 0 && row < 8;

                    Color bgColor;
                    if (isSelected) {
                      bgColor = theme.colorScheme.primaryContainer;
                    } else if (isSameValue) {
                      bgColor = theme.colorScheme.primary
                          .withValues(alpha: 0.12);
                    } else if (isRelated) {
                      bgColor = theme
                          .colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5);
                    } else if ((row ~/ 3 + col ~/ 3).isOdd) {
                      bgColor = theme.colorScheme.surface;
                    } else {
                      bgColor = theme
                          .colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3);
                    }

                    // Error highlighting
                    final isError = value != 0 &&
                        !isOrig &&
                        value != _solution[index] &&
                        _selectedCell == index;

                    Color? textColor;
                    if (isOrig) {
                      textColor = theme.colorScheme.onSurface;
                    } else if (isError) {
                      textColor = theme.colorScheme.error;
                    } else if (value != 0) {
                      textColor = theme.colorScheme.primary;
                    }

                    return GestureDetector(
                      onTap: () => _onCellTap(index),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 100),
                        decoration: BoxDecoration(
                          color: bgColor,
                          border: Border(
                            right: rightBorder
                                ? BorderSide(
                                    color: theme
                                        .colorScheme.outline
                                        .withValues(alpha: 0.5),
                                    width: 2,
                                  )
                                : BorderSide.none,
                            bottom: bottomBorder
                                ? BorderSide(
                                    color: theme
                                        .colorScheme.outline
                                        .withValues(alpha: 0.5),
                                    width: 2,
                                  )
                                : BorderSide.none,
                          ),
                        ),
                        child: value != 0
                            ? Center(
                                child: Text(
                                  '$value',
                                  style: TextStyle(
                                    fontSize: cellSize * 0.55,
                                    fontWeight: isOrig
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                              )
                            : _buildNotes(theme, index, cellSize),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Number pad
          _NumberPad(
            onNumberTap: _onNumberInput,
            onErase: _onErase,
            onHint: _onHint,
            onUndo: _undo,
            onReset: _resetBoard,
            onTogglePencil: _togglePencilMode,
            pencilMode: _pencilMode,
            canUndo: _undoStack.isNotEmpty,
            userGrid: _userGrid,
          ),
          const SizedBox(height: AppSpacing.sm),
          // Hint text
          if (!_gameComplete)
            Center(
              child: Text(
                _selectedCell >= 0 && !_isOriginal[_selectedCell]
                    ? (_pencilMode
                        ? 'Notes mode — tap numbers to toggle pencil marks'
                        : 'Tap a number below to fill the cell')
                    : 'Select an empty cell to begin',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.errors,
    required this.hints,
    required this.time,
    required this.difficulty,
  });

  final int errors;
  final int hints;
  final String time;
  final SudokuDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              icon: Icons.error_outline_rounded,
              value: '$errors',
              label: 'Errors',
              color: theme.colorScheme.error,
            ),
            _StatItem(
              icon: Icons.lightbulb_outline_rounded,
              value: '$hints',
              label: 'Hints',
              color: theme.colorScheme.tertiary,
            ),
            _StatItem(
              icon: Icons.timer_outlined,
              value: time,
              label: 'Time',
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
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
// Number pad
// ---------------------------------------------------------------------------

class _NumberPad extends StatelessWidget {
  const _NumberPad({
    required this.onNumberTap,
    required this.onErase,
    required this.onHint,
    required this.onUndo,
    required this.onReset,
    required this.onTogglePencil,
    required this.pencilMode,
    required this.canUndo,
    required this.userGrid,
  });

  final void Function(int) onNumberTap;
  final VoidCallback onErase;
  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback onTogglePencil;
  final bool pencilMode;
  final bool canUndo;
  final List<int> userGrid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Numbers 1-9
        Row(
          children: List.generate(9, (i) {
            final num = i + 1;
            final count = userGrid.where((v) => v == num).length;
            final exhausted = pencilMode ? false : count >= 9;

            return Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FilledButton(
                    onPressed: () => onNumberTap(num),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: exhausted
                            ? theme.colorScheme.onPrimary
                                .withValues(alpha: 0.3)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Pencil toggle + Erase
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTogglePencil,
                icon: Icon(
                  Icons.edit_off_rounded,
                  size: 18,
                  color: pencilMode
                      ? theme.colorScheme.primary
                      : null,
                ),
                label: Text(
                  pencilMode ? 'Notes On' : 'Notes',
                  style: pencilMode
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  side: pencilMode
                      ? BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onErase,
                icon: const Icon(Icons.backspace_outlined, size: 18),
                label: const Text('Erase'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Undo, Reset, Hint
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canUndo ? onUndo : null,
                icon:
                    const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Undo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onHint,
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                label: const Text('Hint'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Immutable snapshot of the board used for the undo stack.
class _SudokuSnapshot {
  const _SudokuSnapshot({
    required this.grid,
    required this.notes,
    required this.selected,
    required this.errors,
    required this.hints,
  });

  final List<int> grid;
  final List<Set<int>> notes;
  final int selected;
  final int errors;
  final int hints;
}
