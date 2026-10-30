import 'package:flutter/material.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/features/onboarding/screening/data/questionnaires.dart';
import 'package:mindease/features/onboarding/screening/screening_controller.dart';

/// Step 8 — summary of all answers with per-section edit shortcuts.
class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review your answers',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Everything looks good? You can edit any section before we '
            'generate your wellness profile.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            icon: Icons.person_outline_rounded,
            title: 'Personal Information',
            color: theme.colorScheme.primary,
            onEdit: () =>
                controller.jumpToStep(ScreeningController.personalIndex),
            rows: [
              ('Age', c.personal.age.isEmpty ? '—' : c.personal.age),
              ('Gender', c.personal.gender.isEmpty ? '—' : c.personal.gender),
              (
                'Occupation',
                c.personal.occupation.isEmpty ? '—' : c.personal.occupation,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.mood_outlined,
            title: 'Mood Check-In',
            color: theme.colorScheme.tertiary,
            onEdit: () =>
                controller.jumpToStep(ScreeningController.moodIndex),
            rows: [
              (
                'Current mood',
                c.mood.currentMoodId != null
                    ? moodById(c.mood.currentMoodId!).label
                    : '—',
              ),
              (
                'Emotion',
                c.mood.emotion?.isNotEmpty == true ? c.mood.emotion! : '—',
              ),
              (
                'Intensity',
                c.mood.intensityTouched ? '${c.mood.intensity}/10' : '—',
              ),
              (
                'Lately',
                c.mood.frequency ?? '—',
              ),
              (
                'Change',
                c.mood.recentChange ?? '—',
              ),
              if (c.mood.reflection.trim().isNotEmpty)
                (
                  'Reflection',
                  c.mood.reflection.trim().length > 60
                      ? '${c.mood.reflection.trim().substring(0, 60)}…'
                      : c.mood.reflection.trim(),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.fitness_center_outlined,
            color: theme.colorScheme.secondary,
            title: 'Lifestyle Assessment',
            onEdit: () =>
                controller.jumpToStep(ScreeningController.lifestyleIndex),
            rows: [
              for (final q in controller.lifestyleQuestions)
                (
                  q.label,
                  _valueFor(q, c.lifestyle[q.field]),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.sentiment_satisfied_alt_outlined,
            color: theme.colorScheme.primary,
            title: c.catalog.phqTitle,
            onEdit: () => controller.jumpToStep(ScreeningController.phqIndex),
            rows: [
              ('Questions answered', '${_answered(c.phq)} / ${c.phq.length}'),
              ('Score', '${_total(c.phq)} / ${_maxScore(c.phqItems)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.spa_outlined,
            color: theme.colorScheme.tertiary,
            title: c.catalog.gadTitle,
            onEdit: () => controller.jumpToStep(ScreeningController.gadIndex),
            rows: [
              ('Questions answered', '${_answered(c.gad)} / ${c.gad.length}'),
              ('Score', '${_total(c.gad)} / ${_maxScore(c.gadItems)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.thermostat_outlined,
            color: theme.colorScheme.secondary,
            title: c.catalog.pssTitle,
            onEdit: () => controller.jumpToStep(ScreeningController.pssIndex),
            rows: [
              ('Questions answered', '${_answered(c.pss)} / ${c.pss.length}'),
              ('Score', '${_total(c.pss)} / ${_maxScore(c.pssItems)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.wb_sunny_outlined,
            color: theme.colorScheme.primary,
            title: c.catalog.whoTitle,
            onEdit: () => controller.jumpToStep(ScreeningController.whoIndex),
            rows: [
              ('Questions answered', '${_answered(c.who)} / ${c.who.length}'),
              ('Score', '${_total(c.who)} / ${_maxScore(c.whoItems)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  /// Max possible score for a questionnaire: item count x highest option value.
  int _maxScore(List<QuestionnaireItem> items) {
    if (items.isEmpty) return 0;
    final top = items.first.options.isEmpty ? 0 : items.first.options.length - 1;
    return items.length * top;
  }

  String _valueFor(LifestyleQuestion q, double? value) {
    if (value == null) return '—';
    if (q.type == LifestyleInputType.choice) {
      return q.choices.isEmpty
          ? value.toInt().toString()
          : q.choices
                  .where((c) => c.value == value.round())
                  .map((c) => c.label)
                  .firstOrNull ??
              value.toInt().toString();
    }
    final display = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return q.unit.isEmpty ? display : '$display ${q.unit}';
  }

  int _total(List<int> list) =>
      list.where((e) => e >= 0).fold(0, (a, b) => a + b);

  int _answered(List<int> list) => list.where((e) => e >= 0).length;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.onEdit,
    required this.rows,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onEdit;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      icon: icon,
      iconColor: color,
      title: title,
      trailing: TextButton(
        onPressed: onEdit,
        child: const Text('Edit'),
      ),
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
