import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/error/failures.dart';
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

  Timer? _saveTimer;
  bool _submitting = false;
  bool _loading = true;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
    ScreeningSession.firstName ??= '';
    _controller.addListener(_onControllerChanged);
    _ensureCatalog();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Loads the backend questionnaire catalog that drives this run.
  Future<void> _ensureCatalog() async {
    if (_controller.catalogLoaded) {
      setState(() => _loading = false);
      _ensureScreening();
      return;
    }
    setState(() {
      _loading = true;
      _catalogError = null;
    });
    try {
      final api = await mindeaseApi.questionnaireCatalog();
      final catalog = ScreeningCatalog.fromApi(api);
      _controller.loadCatalog(catalog);
      if (!mounted) return;
      setState(() => _loading = false);
      _ensureScreening();
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalogError = 'We couldn’t load the assessment questions. '
            'Please check your connection and try again.';
      });
    }
  }

  /// Creates (or resumes) the server-side draft once per run. Failing quietly
  /// here is fine — the final submit re-creates the draft if needed.
  Future<void> _ensureScreening() async {
    if (ScreeningSession.screeningId != null) return;
    try {
      final created = await mindeaseApi.createScreening();
      ScreeningSession.screeningId ??= created['id'] as String?;
    } on Object {
      // Non-fatal: submit will surface any real failure.
    }
  }

  void _onControllerChanged() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), _autosave);
  }

  Future<void> _autosave() async {
    final id = ScreeningSession.screeningId;
    if (id == null) return;
    try {
      await mindeaseApi.saveScreening(
        id,
        ScreeningSession.payload(_controller),
      );
    } on Object {
      // Non-fatal: the final submit re-saves the complete payload.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _loading || _catalogError != null
              ? () => _exit()
              : _controller.stepIndex == 0
                  ? () => _exit()
                  : () => _controller.back(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          TextButton(onPressed: () => _exit(), child: const Text('Exit')),
        ],
      ),
      body: _catalogError != null
          ? _CatalogErrorState(message: _catalogError!, onRetry: _ensureCatalog)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildScreening(context),
    );
  }

  Widget _buildScreening(BuildContext context) {
    final c = _controller;
    return AnimatedBuilder(
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
              submitting: _submitting,
              onBack: c.back,
              onNext: () => _next(),
            ),
          ],
        );
      },
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

  Future<void> _next() async {
    final c = _controller;
    if (!c.canContinue) return;
    if (c.area != ScreeningArea.review) {
      c.next();
      return;
    }
    await _submit();
  }

  /// Pushes the completed assessment to the backend, then transitions to the
  /// (pending-state) processing screen.
  Future<void> _submit() async {
    if (!_controller.isComplete || _submitting) return;
    _saveTimer?.cancel();
    setState(() => _submitting = true);
    try {
      var id = ScreeningSession.screeningId;
      if (id == null) {
        final created = await mindeaseApi.createScreening();
        id = created['id'] as String?;
        ScreeningSession.screeningId = id;
      }
      if (id == null) {
        throw const ServerFailure(
          'Unable to start an assessment right now. Please try again.',
        );
      }
      await mindeaseApi.saveScreening(
        id,
        ScreeningSession.payload(_controller),
      );
      final submitted = await mindeaseApi.submitScreening(id);
      final processing = submitted['processing'];
      final aiStatus = processing is Map
          ? processing['aiStatus'] as String?
          : null;
      final jobId = processing is Map ? processing['jobId'] as String? : null;
      ScreeningSession.submissionAiStatus =
          aiStatus ?? 'AI_ANALYSIS_PENDING';
      ScreeningSession.aiJobId = jobId;
      if (!mounted) return;
      context.go('/processing');
    } on Failure catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to submit the assessment right now. '
              'Please try again.'),
        ),
      );
    }
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
    final isLastPhq9 = controller.area == ScreeningArea.phq &&
        controller.questionIndex == controller.phqItems.length - 1;

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
          if (isLastPhq9) ...[
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
    final questions = controller.lifestyleQuestions;
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

/// Friendly retry state shown when the questionnaire catalog cannot be loaded.
class _CatalogErrorState extends StatelessWidget {
  const _CatalogErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Unable to load assessment',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Try Again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
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
    required this.submitting,
    required this.onBack,
    required this.onNext,
  });

  final ScreeningController controller;
  final bool submitting;
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
                  onPressed: submitting ? null : onBack,
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
                loading: submitting,
                onPressed:
                    controller.canContinue && !submitting ? onNext : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
