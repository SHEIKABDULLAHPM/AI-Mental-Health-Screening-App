import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_section_card.dart';
import '../data/questionnaires.dart';
import '../screening_controller.dart';

class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.controller, required this.onEdit});

  final ScreeningController controller;
  final ValueChanged<int> onEdit;

  String phqSeverity(int total) {
    if (total <= 4) return 'Minimal';
    if (total <= 9) return 'Mild';
    if (total <= 14) return 'Moderate';
    if (total <= 19) return 'Moderately severe';
    return 'Severe';
  }

  String gadSeverity(int total) {
    if (total <= 4) return 'Minimal';
    if (total <= 9) return 'Mild';
    if (total <= 14) return 'Moderate';
    return 'Severe';
  }

  String pssLevel(int total) {
    if (total <= 13) return 'Low stress';
    if (total <= 26) return 'Moderate stress';
    return 'High stress';
  }

  String whoLevel(int percent) {
    if (percent <= 50) return 'Low wellbeing';
    if (percent < 65) return 'Reduced wellbeing';
    return 'Good wellbeing';
  }

  int sum(List<int> values) =>
      values.where((e) => e >= 0).fold(0, (a, b) => a + b);

  static const _exerciseLabels = [
    'Never',
    '1-2x / week',
    '3-4x / week',
    '5+ / week',
  ];
  static const _waterLabels = [
    '<2 glasses',
    '2-4 glasses',
    '5-7 glasses',
    '8+ glasses',
  ];

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  String lifestyleSummary() {
    final parts = <String>[];
    final sleep = controller.lifestyle[LifestyleField.sleepHours];
    if (sleep != null) parts.add('${_fmt(sleep)} hrs sleep');
    final exercise = controller.lifestyle[LifestyleField.exercise];
    if (exercise != null) parts.add(_exerciseLabels[exercise.round()]);
    final water = controller.lifestyle[LifestyleField.water];
    if (water != null) parts.add(_waterLabels[water.round()]);
    final screen = controller.lifestyle[LifestyleField.screenTime];
    if (screen != null) parts.add('${_fmt(screen)} hrs screens');
    final work = controller.lifestyle[LifestyleField.workingHours];
    if (work != null) parts.add('${_fmt(work)} hrs work/study');
    return parts.isEmpty ? 'Not completed' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phqTotal = sum(controller.phq);
    final gadTotal = sum(controller.gad);
    final pssTotal = sum(controller.pss);
    final whoRaw = sum(controller.who);
    final whoPercent = (whoRaw * 4).clamp(0, 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: AppColors.info,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Please review your answers carefully. You can edit any section before submitting your assessment.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionCard(
          icon: Icons.person_outline_rounded,
          title: 'Personal Information',
          summary: controller.personal.isComplete
              ? 'Age ${controller.personal.age} • ${controller.personal.gender} • ${controller.personal.occupation}'
              : 'Not completed',
          stepIndex: ScreeningController.personalIndex,
          onEdit: onEdit,
        ),
        _SectionCard(
          icon: Icons.fitness_center_outlined,
          title: 'Lifestyle',
          summary: lifestyleSummary(),
          stepIndex: ScreeningController.lifestyleIndex,
          onEdit: onEdit,
        ),
        _SectionCard(
          icon: Icons.mood_outlined,
          title: 'PHQ-9',
          summary:
              '${controller.phq.where((e) => e >= 0).length} of 9 answered',
          result: 'Score $phqTotal • ${phqSeverity(phqTotal)}',
          resultColor: AppColors.scoreColor(100 - phqTotal / 27 * 100),
          stepIndex: ScreeningController.phqIndex,
          onEdit: onEdit,
        ),
        _SectionCard(
          icon: Icons.psychology_outlined,
          title: 'GAD-7',
          summary:
              '${controller.gad.where((e) => e >= 0).length} of 7 answered',
          result: 'Score $gadTotal • ${gadSeverity(gadTotal)}',
          resultColor: AppColors.scoreColor(100 - gadTotal / 21 * 100),
          stepIndex: ScreeningController.gadIndex,
          onEdit: onEdit,
        ),
        _SectionCard(
          icon: Icons.timelapse_outlined,
          title: 'PSS',
          summary:
              '${controller.pss.where((e) => e >= 0).length} of 10 answered',
          result: 'Score $pssTotal • ${pssLevel(pssTotal)}',
          resultColor: AppColors.scoreColor(100 - pssTotal / 40 * 100),
          stepIndex: ScreeningController.pssIndex,
          onEdit: onEdit,
        ),
        _SectionCard(
          icon: Icons.wb_sunny_outlined,
          title: 'WHO-5',
          summary:
              '${controller.who.where((e) => e >= 0).length} of 5 answered',
          result: 'Score $whoPercent% • ${whoLevel(whoPercent)}',
          resultColor: AppColors.scoreColor(whoPercent.toDouble()),
          stepIndex: ScreeningController.whoIndex,
          onEdit: onEdit,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.stepIndex,
    required this.onEdit,
    this.result,
    this.resultColor,
  });

  final IconData icon;
  final String title;
  final String summary;
  final int stepIndex;
  final ValueChanged<int> onEdit;
  final String? result;
  final Color? resultColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppSectionCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => onEdit(stepIndex),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (resultColor ?? scheme.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                result!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: resultColor ?? scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
