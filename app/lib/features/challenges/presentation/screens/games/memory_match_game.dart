import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_result.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_wrapper.dart'
    show GameCompleteExtension;
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// A clean, polished Memory Match game for the challenges feature.
///
/// Pairs of icons are shuffled onto a 4×4 grid. Flip two cards per turn;
/// matching pairs stay revealed. The game ends when all 8 pairs are found.
class MemoryMatchGame extends StatefulWidget {
  const MemoryMatchGame({super.key, this.onGameComplete});

  final void Function(GameResult result)? onGameComplete;

  @override
  State<MemoryMatchGame> createState() => _MemoryMatchGameState();
}

/// Uses [TickerProviderStateMixin] (plural) because we create 16
/// [AnimationController]s — one per card. Using [SingleTickerProviderStateMixin]
/// would crash at runtime with "multiple tickers were created".
class _MemoryMatchGameState extends State<MemoryMatchGame>
    with TickerProviderStateMixin {
  // 8 pairs → 16 cards
  static const int _pairs = 8;
  static const int _cols = 4;

  late List<_CardData> _cards;
  int _firstIndex = -1;
  bool _busy = false;
  int _moves = 0;
  int _matchedPairs = 0;
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _gameStarted = false;
  bool _gameComplete = false;

  // Guards against stale async callbacks (reset/restart) mutating a new game.
  int _epoch = 0;

  // Animation controllers per card for flip effect. Created once and reused
  // across resets to avoid leaking controllers on every new game.
  late List<AnimationController> _flipControllers;
  late List<Animation<double>> _flipAnimations;

  // Scale animation for matched cards
  late AnimationController _matchPopController;
  late Animation<double> _matchPopAnimation;

  // Colors used for each pair
  static const List<Color> _pairColors = [
    Color(0xFFE5484D),
    Color(0xFFFFB020),
    Color(0xFF30A46C),
    Color(0xFF4F6DF5),
    Color(0xFF8B8EE8),
    Color(0xFF6EC6FF),
    Color(0xFFE8913A),
    Color(0xFFD6409F),
  ];

  @override
  void initState() {
    super.initState();
    _flipControllers = List.generate(
      _pairs * 2,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      ),
    );
    _flipAnimations = _flipControllers
        .map((c) => Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ),)
        .toList();

    _matchPopController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _matchPopAnimation = Tween<double>(begin: 1, end: 1.15).animate(
      CurvedAnimation(parent: _matchPopController, curve: Curves.elasticOut),
    );

    _initCards();
  }

  void _initCards() {
    final rng = Random();
    const iconPool = [
      Icons.favorite_rounded,
      Icons.star_rounded,
      Icons.bolt_rounded,
      Icons.diamond_rounded,
      Icons.auto_awesome_rounded,
      Icons.local_fire_department_rounded,
      Icons.eco_rounded,
      Icons.nights_stay_rounded,
    ];

    // Build pairs
    final List<_CardData> deck = [];
    for (int i = 0; i < _pairs; i++) {
      deck.add(_CardData(
          pairIndex: i,
          icon: iconPool[i],
          color: _pairColors[i],
      ),);
      deck.add(_CardData(
          pairIndex: i,
          icon: iconPool[i],
          color: _pairColors[i],
      ),);
    }

    // Shuffle
    deck.shuffle(rng);

    // Reset every flip controller so all cards start face-down.
    for (final c in _flipControllers) {
      c.reset();
    }

    _cards = deck;
    _firstIndex = -1;
    _busy = false;
    _moves = 0;
    _matchedPairs = 0;
    _elapsedSeconds = 0;
    _gameStarted = false;
    _gameComplete = false;
    _epoch++;
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _matchPopController.dispose();
    for (final c in _flipControllers) {
      c.dispose();
    }
    super.dispose();
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

  void _onCardTap(int index) {
    if (_busy) return;
    if (_gameComplete) return;
    if (index < 0 || index >= _cards.length) return;
    if (_cards[index].matched) return;
    if (_firstIndex == index) return;

    HapticFeedback.selectionClick();
    _startTimer();

    if (_firstIndex == -1) {
      // First card of the pair
      setState(() {
        _firstIndex = index;
      });
      _flipControllers[index].forward();
    } else {
      // Second card
      final i1 = _firstIndex;
      final i2 = index;
      setState(() {
        _busy = true;
        _moves++;
      });
      _flipControllers[i2].forward();

      if (_cards[i1].pairIndex == _cards[i2].pairIndex) {
        // Match! Resolve after a short pause.
        final epoch = _epoch;
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted || epoch != _epoch) return;
          setState(() {
            _cards[i1].matched = true;
            _cards[i2].matched = true;
            _matchedPairs++;
            _firstIndex = -1;
            _busy = false;
          });
          HapticFeedback.heavyImpact();
          // Pop animation for matched cards
          _matchPopController.forward().then((_) {
            if (mounted) _matchPopController.reverse();
          });

          if (_matchedPairs == _pairs) {
            _onGameWon();
          }
        });
      } else {
        // No match — flip both back.
        final epoch = _epoch;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted || epoch != _epoch) return;
          // Bounds check in case indices became stale
          if (i1 >= 0 &&
              i1 < _flipControllers.length &&
              i2 >= 0 &&
              i2 < _flipControllers.length) {
            _flipControllers[i1].reverse();
            _flipControllers[i2].reverse();
          }
          setState(() {
            _firstIndex = -1;
            _busy = false;
          });
        });
      }
    }
  }

  void _onGameWon() {
    _timer?.cancel();
    _gameComplete = true;

    final score = max(100, 300 - _moves * 10).clamp(0, 300);
    final stars = _moves <= 14 ? 3 : _moves <= 20 ? 2 : 1;

    // Show completion dialog, then submit
    final epoch = _epoch;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || epoch != _epoch) return;
      _showCompletionDialog(score, stars);
    });
  }

  void _showCompletionDialog(int score, int stars) {
    final theme = Theme.of(context);
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
                Icons.emoji_events_rounded,
                size: 36,
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'You Won!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Star rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    i < stars
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 32,
                    color: i < stars
                        ? const Color(0xFFFFB020)
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$_moves moves · ${_formatTime(_elapsedSeconds)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
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
                  moves: _moves,
                  durationSeconds: _elapsedSeconds,
                  gameType: 'memory_match',
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

  void _resetGame() {
    _timer?.cancel();
    for (final c in _flipControllers) {
      c.reset();
    }
    setState(() => _initCards());
  }

  int get _stars {
    if (_moves <= 14) return 3;
    if (_moves <= 20) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final gridSize = min(screenWidth - AppSpacing.lg * 2, 380.0);
    final cardSize = (gridSize - AppSpacing.sm * (_cols - 1)) / _cols;

    return FeatureScaffold(
      title: 'Memory Match',
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
          // Score bar
          _ScoreBar(
            moves: _moves,
            time: _formatTime(_elapsedSeconds),
            matched: _matchedPairs,
            total: _pairs,
            stars: _stars,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Card grid
          Center(
            child: SizedBox(
              width: gridSize,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _cols,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1,
                ),
                itemCount: _cards.length,
                itemBuilder: (context, index) {
                  return _MemoryCard(
                    data: _cards[index],
                    flipAnimation: _flipAnimations[index],
                    matchPopAnimation: _matchPopAnimation,
                    size: cardSize,
                    onTap: () => _onCardTap(index),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Tip text
          if (!_gameComplete)
            Center(
              child: Text(
                _moves == 0
                    ? 'Tap a card to begin'
                    : _matchedPairs == _pairs - 1
                        ? 'One pair left — you got this!'
                        : '$_matchedPairs of $_pairs pairs found',
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
// Card data
// ---------------------------------------------------------------------------

class _CardData {
  _CardData({
    required this.pairIndex,
    required this.icon,
    required this.color,
  });

  final int pairIndex;
  final IconData icon;
  final Color color;
  bool matched = false;
}

// ---------------------------------------------------------------------------
// Score bar
// ---------------------------------------------------------------------------

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.moves,
    required this.time,
    required this.matched,
    required this.total,
    required this.stars,
  });

  final int moves;
  final String time;
  final int matched;
  final int total;
  final int stars;

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
              icon: Icons.touch_app_rounded,
              value: '$moves',
              label: 'Moves',
              color: theme.colorScheme.primary,
            ),
            _StatItem(
              icon: Icons.timer_outlined,
              value: time,
              label: 'Time',
              color: theme.colorScheme.secondary,
            ),
            _StatItem(
              icon: Icons.check_circle_outline_rounded,
              value: '$matched/$total',
              label: 'Matched',
              color: theme.colorScheme.tertiary,
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
// Animated flip card
// ---------------------------------------------------------------------------

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.data,
    required this.flipAnimation,
    required this.matchPopAnimation,
    required this.size,
    required this.onTap,
  });

  final _CardData data;
  final Animation<double> flipAnimation;
  final Animation<double> matchPopAnimation;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: flipAnimation,
      builder: (context, child) {
        final angle = flipAnimation.value * pi;
        final isFront = angle > pi / 2;

        return GestureDetector(
          onTap: onTap,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: data.matched
                ? ScaleTransition(
                    scale: matchPopAnimation,
                    child: _buildFront(theme),
                  )
                : isFront
                    ? _buildFront(theme)
                    : _buildBack(theme),
          ),
        );
      },
    );
  }

  Widget _buildFront(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: data.matched
            ? data.color.withValues(alpha: 0.12)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: data.matched
              ? data.color.withValues(alpha: 0.4)
              : theme.colorScheme.outline.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: data.matched
            ? []
            : [
                BoxShadow(
                  color:
                      theme.colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Center(
        child: Icon(
          data.icon,
          size: size * 0.42,
          color: data.matched
              ? data.color.withValues(alpha: 0.7)
              : theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildBack(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primary.withValues(alpha: 0.25),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        boxShadow: [
          BoxShadow(
            color:
                theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.question_mark_rounded,
          size: size * 0.35,
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
