import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/features/onboarding/screening/data/questionnaires.dart';
import 'package:mindease/features/onboarding/screening/screening_controller.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';
import 'package:mindease/features/onboarding/screening/steps/personal_info_step.dart';
import 'package:mindease/features/onboarding/screening/steps/review_step.dart';
import 'package:mindease/features/onboarding/screening/widgets/option_picker.dart';
import 'package:mindease/features/onboarding/screening/widgets/slider_field.dart';

/// Multi-step AI mental health screening questionnaire.
class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key});

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  ScreeningController get _controller => ScreeningSession.controller;

  @override
  void initState() {
    super.initState();
    ScreeningSession.firstName ??= '';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: c.stepIndex == 0 ? () => _exit() : () => c.back(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          TextButton(onPressed: () => _exit(), child: const Text('Exit')),
        ],
      ),
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          return Column(
            children: [
              _ProgressHeader(controller: c),
              const Divider(height: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: SizedBox(
                    key: ValueKey((c.area, c.questionIndex)),
                    child: _buildBody(c),
                  ),
                ),
              ),
              _BottomBar(
                controller: c,
                onBack: c.back,
                onNext: () => _next(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(ScreeningController c) {
    switch (c.area) {
      case ScreeningArea.personal:
        return PersonalInfoStep(controller: c);
      case ScreeningArea.review:
        return ReviewStep(controller: c);
      case ScreeningArea.lifestyle:
        return _LifestyleQuestion(controller: c);
      default:
        return _ScaleQuestion(controller: c);
    }
  }

  void _next() {
    final c = _controller;
    if (!c.canContinue) return;
    if (c.area == ScreeningArea.review) {
      context.go('/processing');
      return;
    }
    c.next();
  }

  void _exit() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit screening?'),
        content: const Text(
          'Your progress so far will be lost. You can restart from the '
          'beginning later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep Going'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/dashboard');
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
}

/// One clinically validated question at a time (PHQ-9, GAD-7, PSS, WHO-5).
class _ScaleQuestion extends StatelessWidget {
  const _ScaleQuestion({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = controller.currentQuestion;
    if (question == null) return const SizedBox.shrink();
    final isPhq9 =
        controller.area == ScreeningArea.phq && controller.questionIndex == 8;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question ${controller.questionIndex + 1} of '
            '${controller.currentStepItems}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            question.instruction,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            question.question,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OptionPicker(
            options: question.options,
            selected: controller.currentAnswer == -1
                ? null
                : controller.currentAnswer,
            onSelected: (v) => controller.setQuestionAnswer(v),
          ),
          if (isPhq9) ...[
            const SizedBox(height: AppSpacing.lg),
            _CrisisNote(),
          ],
        ],
      ),
    );
  }
}

/// Lifestyle questions rendered as sliders or choice chips.
class _LifestyleQuestion extends StatelessWidget {
  const _LifestyleQuestion({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const questions = lifestyleQuestions;
    final q = questions[controller.questionIndex];
    final current = controller.lifestyle[q.field];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question ${controller.questionIndex + 1} of '
            '${controller.currentStepItems}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            q.hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            q.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (q.type == LifestyleInputType.slider)
            SliderField(
              value: current ?? q.min,
              min: q.min,
              max: q.max,
              step: q.step,
              unit: q.unit,
              onChanged: (v) => controller.setLifestyle(q.field, v),
            )
          else
            OptionPicker(
              options: [
                for (final choice in q.choices)
                  ScaleOption(choice.value, choice.label),
              ],
              selected: current?.round(),
              onSelected: (v) => controller.setLifestyle(q.field, v.toDouble()),
            ),
        ],
      ),
    );
  }
}

/// Gentle support note shown with the PHQ-9 item about self-harm.
class _CrisisNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.favorite_rounded,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'If you or someone you know needs support right now, please '
              'reach out to a trusted person or a local crisis service.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.areaLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                controller.stepLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: controller.progress,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.onBack,
    required this.onNext,
  });

  final ScreeningController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isFirst = controller.area == ScreeningArea.personal;
    final isReview = controller.area == ScreeningArea.review;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!isFirst) ...[
              Expanded(
                child: AppButton(
                  label: 'Back',
                  variant: AppButtonVariant.outlined,
                  onPressed: onBack,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              flex: 2,
              child: AppButton(
                label: isReview ? 'Submit Assessment' : 'Continue',
                icon: isReview
                    ? Icons.rocket_launch_rounded
                    : Icons.arrow_forward_rounded,
                onPressed: controller.canContinue ? onNext : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
