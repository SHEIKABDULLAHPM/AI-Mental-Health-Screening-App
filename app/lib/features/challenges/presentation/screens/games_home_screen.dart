import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Supported game definitions for challenge integration.
class _GameDef {
  const _GameDef({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    required this.color,
    required this.benefits,
  });

  final String title;
  final String description;
  final IconData icon;
  final String route;
  final Color color;
  final String benefits;
}

const _games = [
  _GameDef(
    title: '2048',
    description: 'Slide tiles to merge numbers and reach 2048.',
    icon: Icons.grid_4x4_rounded,
    route: '/challenges/game/2048',
    color: Color(0xFFFFB020),
    benefits: 'Focus · Strategy · Numeracy',
  ),
  _GameDef(
    title: 'Sudoku',
    description: 'Fill the 9×9 grid with logic and patience.',
    icon: Icons.grid_3x3_rounded,
    route: '/challenges/game/sudoku',
    color: Color(0xFF4F6DF5),
    benefits: 'Logic · Concentration · Patience',
  ),
  _GameDef(
    title: 'Tic-Tac-Toe',
    description: 'Classic Xs and Os — beat the AI opponent.',
    icon: Icons.close_fullscreen_rounded,
    route: '/challenges/game/tic-tac-toe',
    color: Color(0xFF30A46C),
    benefits: 'Strategy · Quick Thinking · Planning',
  ),
  _GameDef(
    title: 'Memory Match',
    description: 'Find matching pairs of hidden cards.',
    icon: Icons.style_rounded,
    route: '/challenges/game/memory',
    color: Color(0xFFD6409F),
    benefits: 'Memory · Attention · Recall',
  ),
];

/// Games hub screen accessible from challenge details.
class GamesHomeScreen extends StatelessWidget {
  const GamesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FeatureScaffold(
      title: 'Games',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          // Wellness context banner
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Games for Wellness',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Each game targets cognitive skills that support your mental wellbeing. Play regularly to build focus, memory, and resilience.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ..._games.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(g.route),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: g.color.withValues(alpha: 0.14),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                            child: Icon(g.icon, color: g.color, size: 26),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  g.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  g.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  g.benefits,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: g.color,
                                    fontWeight: FontWeight.w600,
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
              ),
            ),
        ],
      ),
    );
  }
}
