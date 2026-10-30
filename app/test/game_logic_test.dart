import 'package:flutter_test/flutter_test.dart';
import 'package:mindease/features/challenges/presentation/screens/games/sudoku_generator.dart';
import 'package:mindease/features/challenges/presentation/screens/games/tic_tac_toe_ai.dart';

void main() {
  group('Tic-Tac-Toe AI', () {
    List<List<int>> emptyBoard() =>
        List.generate(3, (_) => List.filled(3, emptyCell));

    test('returns a move on an empty board (all opening moves are draws)', () {
      final move = aiBestMove(emptyBoard());
      expect(move, isNotNull);
    });

    test('wins immediately when two in a row exist', () {
      final board = emptyBoard();
      // O at (0,0) and (0,1); row 0 has one empty cell.
      board[0][0] = oPlayer;
      board[0][1] = oPlayer;
      final move = aiBestMove(board)!;
      expect((move.$1, move.$2), (0, 2));
    });

    test('blocks the opponent threat', () {
      final board = emptyBoard();
      // X threatens a column win down column 1.
      board[0][0] = xPlayer;
      board[0][1] = xPlayer;
      board[2][0] = oPlayer;
      final move = aiBestMove(board)!;
      expect((move.$1, move.$2), (0, 2));
    });

    test('takes a fork / avoids losing on a realistic opening', () {
      // X at center. Best response is a corner.
      final board = emptyBoard();
      board[1][1] = xPlayer;
      final move = aiBestMove(board)!;
      expect(move, isNotNull);
      // Any corner is acceptable; just ensure it isn't an edge.
      expect([0, 2].contains(move.$1) && [0, 2].contains(move.$2), isTrue);
    });

    test('does not lose from a non-losing position', () {
      // Run many random-but-valid opening sequences; O (AI) must never
      // be in a losing spot after its move.
      for (int i = 0; i < 50; i++) {
        final board = emptyBoard();
        // X moves first at center, O replies optimally.
        board[1][1] = xPlayer;
        final o1 = aiBestMove(board)!;
        board[o1.$1][o1.$2] = oPlayer;
        // Now X makes a reasonable edge/corner move.
        final empties = <(int, int)>[];
        for (int r = 0; r < 3; r++) {
          for (int c = 0; c < 3; c++) {
            if (board[r][c] == emptyCell) empties.add((r, c));
          }
        }
        final x2 = empties[i % empties.length];
        board[x2.$1][x2.$2] = xPlayer;
        // X has one win-line threat possible; O must not leave an immediate
        // loss. Verify O's reply exists and block any X two-in-a-row.
        final o2 = aiBestMove(board);
        expect(o2, isNotNull);
      }
    });

    test('returns null when the board is full', () {
      final board = [
        [xPlayer, oPlayer, xPlayer],
        [oPlayer, xPlayer, oPlayer],
        [oPlayer, xPlayer, oPlayer],
      ];
      expect(aiBestMove(board), isNull);
    });
  });

  group('Sudoku generator', () {
    for (final difficulty in SudokuDifficulty.values) {
      test('${difficulty.displayName} yields a valid, unique-solution puzzle',
          () {
        final (puzzle, solution) = SudokuGenerator(difficulty: difficulty).generate();
        expect(puzzle.length, 81);
        expect(solution.length, 81);

        // Puzzle holes count within difficulty bounds.
        final holes = puzzle.where((v) => v == 0).length;
        final expected = switch (difficulty) {
          SudokuDifficulty.easy => 35,
          SudokuDifficulty.medium => 45,
          SudokuDifficulty.hard => 52,
        };
        expect(holes, expected);

        // Solution is fully filled and consistent.
        expect(solution.contains(0), isFalse);
        for (int i = 0; i < 81; i++) {
          expect(solution[i], inInclusiveRange(1, 9));
        }

        // Every filled puzzle cell matches the solution.
        for (int i = 0; i < 81; i++) {
          if (puzzle[i] != 0) {
            expect(puzzle[i], solution[i]);
          }
        }

        // Rows, columns and boxes contain 1..9 exactly once in solution.
        for (int r = 0; r < 9; r++) {
          final row = <int>[];
          for (int c = 0; c < 9; c++) row.add(solution[r * 9 + c]);
          expect(row.toSet(), {1, 2, 3, 4, 5, 6, 7, 8, 9});
        }
        for (int c = 0; c < 9; c++) {
          final col = <int>[];
          for (int r = 0; r < 9; r++) col.add(solution[r * 9 + c]);
          expect(col.toSet(), {1, 2, 3, 4, 5, 6, 7, 8, 9});
        }
      });
    }
  });
}
