import 'package:flutter/material.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';

/// Presentation-neutral view of one analysis result.
///
/// The three analysis endpoints return different payloads; this adapter lets a
/// single card render all of them, so mental, physical and combined results
/// look and behave the same way.
class WellnessAnalysisResult {
  const WellnessAnalysisResult({
    required this.title,
    required this.available,
    required this.generatedBy,
    required this.analyzedAt,
    this.narrative,
    this.insight,
    this.advice = const [],
    this.recommendations = const [],
    this.focusAreas = const [],
    this.nextActions = const [],
    this.comparison,
    this.note,
    this.goalTargetSuggestions = const [],
  });

  final String title;
  final bool available;
  final String generatedBy;
  final DateTime analyzedAt;
  final String? narrative;

  /// The existing free-text insight, used when no narrative came back.
  final String? insight;
  final List<WellnessAnalysisAdvice> advice;
  final List<String> recommendations;
  final List<String> focusAreas;
  final List<String> nextActions;
  final WellnessAnalysisComparison? comparison;
  final String? note;
  final List<GoalTargetSuggestion> goalTargetSuggestions;

  String get body {
    final text = narrative?.trim();
    if (text != null && text.isNotEmpty) return text;
    return insight?.trim() ?? '';
  }

  factory WellnessAnalysisResult.mental(MentalWellnessAnalysis a) {
    return WellnessAnalysisResult(
      title: 'Mental wellness analysis',
      available: a.available,
      generatedBy: a.generatedBy,
      analyzedAt: a.analyzedAt,
      narrative: a.insight,
      advice: a.advice,
      recommendations: a.recommendations,
      focusAreas: a.focusAreas,
      nextActions: a.nextActions,
      comparison: a.comparison,
      note: a.note,
      goalTargetSuggestions: a.goalTargetSuggestions,
    );
  }

  factory WellnessAnalysisResult.physical(PhysicalWellnessAnalysis a) {
    final detected = a.patterns.isEmpty ? null : a.patterns.join(' ');
    return WellnessAnalysisResult(
      title: 'Physical wellness analysis',
      available: a.available,
      generatedBy: a.generatedBy,
      analyzedAt: a.analyzedAt,
      narrative: a.narrative == null || a.narrative!.trim().isEmpty
          ? detected
          : a.narrative,
      insight: detected,
      advice: a.advice,
      recommendations: a.recommendations,
      focusAreas: a.focusAreas,
      nextActions: a.nextActions,
      comparison: a.comparison,
      note: a.note,
      goalTargetSuggestions: a.goalTargetSuggestions,
    );
  }

  factory WellnessAnalysisResult.combined(CombinedWellnessAnalysis a) {
    return WellnessAnalysisResult(
      title: 'Combined mental + physical analysis',
      available: a.available,
      generatedBy: a.generatedBy,
      analyzedAt: a.analyzedAt,
      narrative: a.narrative,
      advice: a.advice.isEmpty
          ? a.suggestions
              .map((s) => WellnessAnalysisAdvice(
                    title: s.title,
                    description: s.description,
                    category: s.category,
                  ))
              .toList()
          : a.advice,
      recommendations: a.suggestions.map((s) => s.title).toList(),
      focusAreas: a.focusAreas,
      nextActions: a.nextActions,
      comparison: a.comparison,
      note: a.note,
      goalTargetSuggestions: a.goalTargetSuggestions,
    );
  }
}

/// Renders one analysis result, including the comparison with history.
///
/// Wording provenance is always shown, so rule-based copy is never presented
/// as AI-generated. A missing comparison is stated as a first analysis rather
/// than hidden.
class WellnessAnalysisResultCard extends StatelessWidget {
  const WellnessAnalysisResultCard({super.key, required this.result});

  final WellnessAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generatedLabel = result.generatedBy == 'llm'
        ? 'AI-personalised wording'
        : result.generatedBy == 'ai'
            ? 'AI analysis'
            : 'Generated from your data';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    result.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$generatedLabel · ${_formatWhen(result.analyzedAt)}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (!result.available) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                result.note?.trim().isNotEmpty == true
                    ? result.note!.trim()
                    : 'There is not enough recorded data for this analysis yet.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Record a little more data, then run the analysis again.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ] else ...[
              if (result.body.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(result.body,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
              ],
              if (result.focusAreas.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final area in result.focusAreas)
                      Chip(
                        label: Text(area, style: theme.textTheme.labelSmall),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              if (result.advice.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, 'Recommendations'),
                for (final item in result.advice)
                  _bullet(
                    context,
                    title: item.title,
                    detail: item.description,
                  ),
              ] else if (result.recommendations.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, 'Recommendations'),
                for (final item in result.recommendations)
                  _bullet(context, title: item, detail: null),
              ],
              if (result.nextActions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, 'Your targets'),
                for (final action in result.nextActions)
                  _bullet(context, title: action, detail: null),
              ],
              if (result.goalTargetSuggestions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _sectionTitle(context, 'AI Recommended Targets'),
                for (final goal in result.goalTargetSuggestions)
                  _goalTargetTile(context, goal),
              ],
              const SizedBox(height: AppSpacing.md),
              _ComparisonSection(comparison: result.comparison),
              if (result.note != null && result.note!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  result.note!.trim(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _formatWhen(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static Widget _sectionTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static Widget _bullet(BuildContext context,
      {required String title, String? detail}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.success),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (detail != null && detail.trim().isNotEmpty)
                  Text(
                    detail,
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
    );
  }
  static Widget _goalTargetTile(BuildContext context, GoalTargetSuggestion goal) {
    final theme = Theme.of(context);
    final label = switch (goal.metric) {
      'dailySteps' => 'Daily steps target',
      'dailyActiveMinutes' => 'Daily active exercise target',
      'weeklyWorkoutMinutes' => 'Weekly workout target',
      'dailySleepMinutes' => 'Daily sleep target',
      'dailyHydrationMl' => 'Daily hydration target',
      _ => goal.metric,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.flag_circle_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 10,
                                    color: theme.colorScheme.onTertiaryContainer,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'AI Target',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${goal.value} ${goal.unit}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (goal.rationale.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      goal.rationale,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({required this.comparison});

  final WellnessAnalysisComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = comparison;

    if (data == null || !data.hasPrevious) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          data?.summary ??
              'First stored analysis — the next run will be compared against this one.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.trending_up_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text('Progress since last time',
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ],
        ),
        if (data.summary != null && data.summary!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(data.summary!,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45)),
        ],
        const SizedBox(height: AppSpacing.sm),
        for (final change in data.changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  switch (change.direction) {
                    'IMPROVED' => Icons.arrow_upward_rounded,
                    'DECLINED' => Icons.arrow_downward_rounded,
                    _ => Icons.remove_rounded,
                  },
                  size: 14,
                  color: switch (change.direction) {
                    'IMPROVED' => AppColors.success,
                    'DECLINED' => AppColors.error,
                    _ => theme.colorScheme.onSurfaceVariant,
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${change.aspect}: ${change.previous} → ${change.current}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (data.habitInsights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          for (final hint in data.habitInsights)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                hint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Opens the analysis result in a dismissible sheet.
Future<void> showWellnessAnalysisSheet(
  BuildContext context,
  WellnessAnalysisResult result,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (scrollContext, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        children: [WellnessAnalysisResultCard(result: result)],
      ),
    ),
  );
}
