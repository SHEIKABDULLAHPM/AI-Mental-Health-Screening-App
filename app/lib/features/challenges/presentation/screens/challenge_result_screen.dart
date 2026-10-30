import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Post-completion result screen for a challenge.
class ChallengeResultScreen extends StatelessWidget {
  const ChallengeResultScreen({
    super.key,
    required this.challengeTitle,
    required this.pointsEarned,
    this.badgeLabel,
    this.streakDays,
    this.message,
  });

  final String challengeTitle;
  final int pointsEarned;
  final String? badgeLabel;
  final int? streakDays;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FeatureScaffold(
      title: 'Challenge Result',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          const SizedBox(height: AppSpacing.xl),
          // Trophy icon
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.emoji_events_rounded,
                size: 44,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Title
          Text(
            'Challenge Completed',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            challengeTitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Points earned
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.stars_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$pointsEarned points earned',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (streakDays != null && streakDays! > 0)
                          Text(
                            '$streakDays-day streak',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Badge
          if (badgeLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.military_tech_rounded,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Badge: $badgeLabel',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // Message
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          // Action buttons
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go('/challenges'),
              child: const Text('Back to Challenges'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}
