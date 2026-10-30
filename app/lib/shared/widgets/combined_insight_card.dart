import 'package:flutter/material.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';

/// Combined mental + physical insight card.
///
/// The label above the text is derived from [MindeaseCombinedInsight.generatedBy]
/// so deterministic rule-based copy is never presented as generative AI.
/// Coverage is shown exactly as the server reported it, including zero days.
class CombinedInsightCard extends StatelessWidget {
  const CombinedInsightCard({super.key, required this.insight});

  final MindeaseCombinedInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrative = insight.narrative?.trim() ?? '';
    if (!insight.available || narrative.isEmpty) {
      return const SizedBox.shrink();
    }
    final sourceLabel =
        insight.isAiWording ? 'AI-personalised' : 'Based on your data';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.psychology_alt_rounded,
                    size: 20,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mind–body insight',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        sourceLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              narrative,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            if (insight.suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final suggestion in insight.suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.title,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (suggestion.description.isNotEmpty)
                              Text(
                                suggestion.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (insight.coverage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _coverageLine(insight.coverage!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (insight.note != null && insight.note!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                insight.note!.trim(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _coverageLine(MindeaseInsightCoverage coverage) {
    final nights = coverage.daysWithSleep == 1 ? 'night' : 'nights';
    return 'Last ${coverage.windowDays} days: '
        'activity ${coverage.daysWithActivity} · '
        'sleep ${coverage.daysWithSleep} $nights · '
        'hydration ${coverage.daysWithHydration} · '
        'mood ${coverage.moodCheckins}';
  }
}
