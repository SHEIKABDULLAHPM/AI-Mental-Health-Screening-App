library;

import 'dart:math';

/// Pure Tic-Tac-Toe AI. Top-level functions so they can run in a background
/// isolate via `compute` and be unit-tested in isolation.
///
/// Board encoding (3×3 lists of ints):
///   * `xPlayer`  = 0 → X (the human)
///   * `oPlayer`  = 1 → O (the AI)
///   * `emptyCell` = 2 → empty

const int xPlayer = 0;
const int oPlayer = 1;
const int emptyCell = 2;

/// Returns the best `(row, col)` for the AI (O) to play, or null when the
/// board is full. Uses minimax so the AI wins whenever possible, blocks the
/// human's immediate wins, and never loses from a non-losing position.
(int, int)? aiBestMove(List<List<int>> board) {
  int bestScore = -1000;
  (int, int)? best;

  for (int r = 0; r < 3; r++) {
    for (int c = 0; c < 3; c++) {
      if (board[r][c] == emptyCell) {
        board[r][c] = oPlayer;
        final score = _minimax(board, 0, false);
        board[r][c] = emptyCell;
        if (score > bestScore) {
          bestScore = score;
          best = (r, c);
        }
      }
    }
  }
  return best;
}

int _minimax(List<List<int>> board, int depth, bool isMaximizing) {
  final winner = _winner(board);
  if (winner == oPlayer) return 10 - depth;
  if (winner == xPlayer) return depth - 10;
  if (_full(board)) return 0;

  if (isMaximizing) {
    int best = -1000;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        if (board[r][c] == emptyCell) {
          board[r][c] = oPlayer;
          best = max(best, _minimax(board, depth + 1, false));
          board[r][c] = emptyCell;
        }
      }
    }
    return best;
  } else {
    int best = 1000;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        if (board[r][c] == emptyCell) {
          board[r][c] = xPlayer;
          best = min(best, _minimax(board, depth + 1, true));
          board[r][c] = emptyCell;
        }
      }
    }
    return best;
  }
}

int? _winner(List<List<int>> board) {
  for (int i = 0; i < 3; i++) {
    if (board[i][0] != emptyCell &&
        board[i][0] == board[i][1] &&
        board[i][1] == board[i][2]) {
      return board[i][0];
    }
    if (board[0][i] != emptyCell &&
        board[0][i] == board[1][i] &&
        board[1][i] == board[2][i]) {
      return board[0][i];
    }
  }
  if (board[0][0] != emptyCell &&
      board[0][0] == board[1][1] &&
      board[1][1] == board[2][2]) {
    return board[0][0];
  }
  if (board[0][2] != emptyCell &&
      board[0][2] == board[1][1] &&
      board[1][1] == board[2][0]) {
    return board[0][2];
  }
  return null;
}

bool _full(List<List<int>> board) {
  for (final row in board) {
    if (row.contains(emptyCell)) return false;
  }
  return true;
}
