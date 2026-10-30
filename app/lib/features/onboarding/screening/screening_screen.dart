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
import 'package:mindease/features/mood_tracking/domain/emotion/fer_preloader.dart';
import 'package:mindease/features/onboarding/screening/steps/mood_assessment_step.dart';
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
  // Duplicate-call prevention for the onboarding mood write: exactly one
  // analyze + one record per submission attempt chain; retries reuse the id.
  bool _moodPersistAttempted = false;

  /// Stable idempotency key for the onboarding camera emotion event: one per
  /// screening-screen instance, so a retried submit replays the same event
  /// instead of duplicating it (the backend dedupes by key).
  late final String _cameraEventKey =
      'ob-cam-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    ScreeningSession.firstName ??= '';
    _controller.addListener(_onControllerChanged);
    // Fire-and-forget: warm the emotion interpreter while the user answers
    // the questionnaire, so the optional camera step opens ready. Never
    // throws; the camera screen falls back to its own load path.
    FerPreloader.warmup();
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
      _ensureMoodHistory();
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
      _ensureMoodHistory();
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalogError = 'We couldn’t load the assessment questions. '
            'Please check your connection and try again.';
      });
    }
  }

  /// Prefetches the onboarding mood context once per run so the mood step can
  /// show history instead of asking redundant questions. Best-effort: a
  /// failure degrades to a manual mood step and never blocks onboarding.
  Future<void> _ensureMoodHistory() async {
    final h = _controller.moodHistory;
    if (h.loaded || h.loading) return;
    _controller.setMoodHistoryLoading();
    try {
      final summary = await featureApi.getOnboardingMoodSummary();
      if (!mounted) return;
      _controller.applyMoodHistory(summary);
    } on Object {
      if (!mounted) return;
      _controller.setMoodHistoryError(
        'Previous check-ins are unavailable.',
      );
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
      case ScreeningArea.mood:
        return MoodAssessmentStep(controller: c);
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
      // Persist the onboarding mood as a canonical mood entry first so it
      // joins the user's real history (single analyze + single record per
      // submission chain; retries reuse the linked id — never duplicates).
      await _persistOnboardingMood();
      _saveTimer?.cancel();
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

  /// Persists the onboarding mood snapshot as a real mood entry.
  ///
  /// The user's self-reported mood is always the primary signal. Supporting
  /// signals (camera observation and/or reflection text) enrich it through the
  /// existing single `/moods/analyze` fusion — low confidence, conflicts, or
  /// unavailability degrade to MANUAL, never block, never invent. Exactly one
  /// analyze, one record, and one emotion event per submission chain; retries
  /// reuse the linked id. A mood-write failure never blocks the assessment:
  /// the snapshot still travels inside the screening payload.
  Future<void> _persistOnboardingMood() async {
    final c = _controller;
    if (!c.mood.isComplete) return;
    if (_moodPersistAttempted && c.mood.linkedMoodEntryId != null) return;
    _moodPersistAttempted = true;

    final moodId = c.mood.currentMoodId!;
    final emotion = c.mood.emotion;
    final hasText = c.mood.reflection.trim().isNotEmpty;
    final note = hasText ? c.mood.reflection.trim() : null;
    final intensity =
        c.mood.intensityTouched ? c.mood.intensity : null;
    final camera = c.mood.cameraResult;
    final hasCamera = camera != null && camera.emotion != 'unknown';

    try {
      // The fusion call is an *enrichment*, not a prerequisite. If the AI
      // service is slow or unavailable the check-in is still recorded below,
      // carrying the camera observation the user actually produced. Previously
      // a timeout here skipped recordMood entirely and lost the whole entry.
      Map<String, dynamic>? analysis;
      if (hasText || hasCamera) {
        try {
          analysis = await featureApi.analyzeMood(
            mood: moodId,
            emotion: emotion,
            note: note,
            cameraObservation: hasCamera ? camera.toMap() : null,
          );
        } on Object {
          analysis = null;
        }
      }

      if (analysis != null) {
        final sourcesUsed =
            (analysis['sources_used'] as List?)?.cast<String>() ?? [];
        final textAnalysis =
            analysis['text_analysis'] as Map<String, dynamic>?;
        final cameraAnalysis =
            analysis['camera_analysis'] as Map<String, dynamic>?;
        final confidence =
            (analysis['confidence'] as num?)?.toDouble();
        final observations = <Map<String, dynamic>>[];
        if (textAnalysis != null) {
          observations.add({
            'source': textAnalysis['source'] ?? 'TEXT',
            'emotion': textAnalysis['emotion'] ?? 'neutral',
            'confidence': textAnalysis['emotion_confidence'] ?? 0.0,
            'sentiment': textAnalysis['sentiment'],
            'sentimentConfidence': textAnalysis['sentiment_confidence'],
            'suggestedMood': textAnalysis['suggested_mood'],
            'modelVersion': textAnalysis['model_version'],
          });
        }
        if (cameraAnalysis != null) {
          observations.add({
            'source': cameraAnalysis['source'] ?? 'CAMERA',
            'emotion': cameraAnalysis['emotion'] ?? 'neutral',
            'confidence': cameraAnalysis['confidence'] ?? 0.0,
            'suggestedMood': cameraAnalysis['suggested_mood'],
            'modelVersion': cameraAnalysis['model_version'],
          });
        }
        // Source mirrors the standalone check-in exactly: MULTIMODAL only
        // when both signals participated, otherwise the single used source.
        final String source;
        if (sourcesUsed.contains('TEXT') &&
            sourcesUsed.contains('CAMERA')) {
          source = 'MULTIMODAL';
        } else if (sourcesUsed.contains('CAMERA')) {
          source = 'CAMERA';
        } else if (sourcesUsed.contains('TEXT')) {
          source = 'TEXT';
        } else {
          source = 'MANUAL';
        }
        final created = await featureApi.recordMood(
          mood: moodId,
          emotion: emotion,
          note: note,
          source: source,
          confidence: confidence,
          // The user's own selection is already the stored mood; fusing now
          // echoes it back, so persist the AI's separate read instead.
          aiSuggestedMood: analysis['ai_suggested_mood'] as String?,
          aiObservations: observations.isEmpty ? null : observations,
          intensity: intensity,
        );
        c.setLinkedMoodEntryId(created?['id'] as String?);
      } else if (hasText || hasCamera) {
        // Fusion unavailable: persist the check-in from what we know locally.
        // No AI mood is invented — only the camera result the device itself
        // produced is attached as an observation.
        final created = await featureApi.recordMood(
          mood: moodId,
          emotion: emotion,
          note: note,
          source: hasCamera ? 'CAMERA' : 'TEXT',
          aiObservations: hasCamera
              ? [
                  {
                    'source': 'CAMERA',
                    'emotion': camera.emotion,
                    'confidence': camera.confidence,
                    'suggestedMood': null,
                    'modelVersion': camera.modelVersion,
                  },
                ]
              : null,
          intensity: intensity,
        );
        c.setLinkedMoodEntryId(created?['id'] as String?);
      } else {
        final created = await featureApi.recordMood(
          mood: moodId,
          emotion: emotion,
          source: 'MANUAL',
          intensity: intensity,
        );
        c.setLinkedMoodEntryId(created?['id'] as String?);
      }
      // Immutable camera telemetry, best-effort: one stable key per
      // onboarding run so a retry replays instead of duplicating (the
      // backend dedupes by key). Must never fail the mood write above.
      if (hasCamera) {
        try {
          await featureApi.recordEmotionEvent(
            camera.toEventMap(
              capturedAt: DateTime.now().toUtc().toIso8601String(),
              idempotencyKey: _cameraEventKey,
            ),
          );
        } on Object {
          // Telemetry only — the mood record is already persisted.
        }
      }
    } on Object {
      // Best-effort: the screening payload still carries the snapshot and the
      // backend derives trend/history from whatever exists server-side.
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
