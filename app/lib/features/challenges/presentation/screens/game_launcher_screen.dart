import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Game selector screen for challenge-integrated game play.
///
/// When reached via the challenge flow, this routes the user to the
/// appropriate game with their challengeId so results are submitted
/// against the active challenge.
class GameLauncherScreen extends StatelessWidget {
  const GameLauncherScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FeatureScaffold(
      title: 'Choose a Game',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(
            'Select a game to play for this challenge.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _GameOption(
            title: '2048',
            description: 'Slide and merge tiles to reach 2048.',
            icon: Icons.grid_4x4_rounded,
            color: const Color(0xFFFFB020),
            onTap: () => context.push(
              '/challenges/game/2048?challengeId=$challengeId',
            ),
          ),
          _GameOption(
            title: 'Sudoku',
            description: 'Fill the 9×9 grid with logic.',
            icon: Icons.grid_3x3_rounded,
            color: const Color(0xFF4F6DF5),
            onTap: () => context.push(
              '/challenges/game/sudoku?challengeId=$challengeId',
            ),
          ),
          _GameOption(
            title: 'Tic-Tac-Toe',
            description: 'Classic Xs and Os — play vs AI or two players.',
            icon: Icons.close_fullscreen_rounded,
            color: const Color(0xFF30A46C),
            onTap: () => context.push(
              '/challenges/game/tic-tac-toe?challengeId=$challengeId',
            ),
          ),
          _GameOption(
            title: 'Memory Match',
            description: 'Find matching pairs of hidden cards.',
            icon: Icons.style_rounded,
            color: const Color(0xFFD6409F),
            onTap: () => context.push(
              '/challenges/game/memory?challengeId=$challengeId',
            ),
          ),
        ],
      ),
    );
  }
}

class _GameOption extends StatelessWidget {
  const _GameOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
