import 'dart:math';

/// Pure-Dart Sudoku puzzle generator.
///
/// Generates a valid, solvable Sudoku puzzle with a unique solution by
/// filling a board via backtracking, then removing cells according to the
/// chosen difficulty level.
class SudokuGenerator {
  SudokuGenerator({this.difficulty = SudokuDifficulty.medium});

  final SudokuDifficulty difficulty;

  /// Number of cells to remove based on difficulty.
  int get _holes => switch (difficulty) {
        SudokuDifficulty.easy => 35,
        SudokuDifficulty.medium => 45,
        SudokuDifficulty.hard => 52,
      };

  /// Returns [puzzle, solution] — each a flat 81-length list of ints (0 = empty).
  (List<int> puzzle, List<int> solution) generate() {
    final rng = Random();
    final board = List.filled(81, 0);
    _fillBoard(board, rng);
    final solution = List<int>.from(board);

    // Remove cells
    final puzzle = List<int>.from(board);
    final indices = List<int>.generate(81, (i) => i)..shuffle(rng);
    int removed = 0;
    for (final i in indices) {
      if (removed >= _holes) break;
      final backup = puzzle[i];
      puzzle[i] = 0;

      // Verify unique solution
      if (_countSolutions(List<int>.from(puzzle)) == 1) {
        removed++;
      } else {
        puzzle[i] = backup;
      }
    }

    return (puzzle, solution);
  }

  // ---------- Backtracking solver ----------

  bool _fillBoard(List<int> board, Random rng) {
    final empty = board.indexOf(0);
    if (empty == -1) return true;

    final nums = List<int>.generate(9, (i) => i + 1)..shuffle(rng);
    for (final n in nums) {
      if (_isValid(board, empty, n)) {
        board[empty] = n;
        if (_fillBoard(board, rng)) return true;
        board[empty] = 0;
      }
    }
    return false;
  }

  bool _isValid(List<int> board, int index, int value) {
    final row = index ~/ 9;
    final col = index % 9;

    // Row
    for (int c = 0; c < 9; c++) {
      if (board[row * 9 + c] == value) return false;
    }
    // Column
    for (int r = 0; r < 9; r++) {
      if (board[r * 9 + col] == value) return false;
    }
    // 3×3 box
    final boxRow = (row ~/ 3) * 3;
    final boxCol = (col ~/ 3) * 3;
    for (int r = boxRow; r < boxRow + 3; r++) {
      for (int c = boxCol; c < boxCol + 3; c++) {
        if (board[r * 9 + c] == value) return false;
      }
    }
    return true;
  }

  int _countSolutions(List<int> board, {int limit = 2}) {
    final empty = board.indexOf(0);
    if (empty == -1) return 1;

    int count = 0;
    for (int n = 1; n <= 9; n++) {
      if (_isValid(board, empty, n)) {
        board[empty] = n;
        count += _countSolutions(board, limit: limit - count);
        board[empty] = 0;
        if (count >= limit) return count;
      }
    }
    return count;
  }
}

enum SudokuDifficulty {
  easy,
  medium,
  hard;

  String get displayName => name[0].toUpperCase() + name.substring(1);
}
