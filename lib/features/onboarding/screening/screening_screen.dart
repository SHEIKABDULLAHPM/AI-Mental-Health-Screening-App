import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/smooth_page_route.dart';
import 'ai_processing/ai_processing_screen.dart';
import 'data/questionnaires.dart';
import 'screening_controller.dart';
import 'steps/personal_info_step.dart';
import 'steps/review_step.dart';
import 'widgets/lifestyle_question_view.dart';
import 'widgets/one_question_screen.dart';

class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key});

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  final ScreeningController _controller = ScreeningController();
  Timer? _advanceTimer;
  bool _submitting = false;

  static const String _safetyNote =
      'If you are having thoughts of hurting yourself, please reach out for help right away. '
      'Contact a trusted person, a local crisis helpline, or your nearest emergency service. You are not alone.';

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSelect(int value) {
    _controller.setQuestionAnswer(value);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted && _controller.canContinue) _controller.next();
    });
  }

  void _handleBack() {
    if (_controller.area == ScreeningArea.personal) {
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Exit Screening?'),
          content: const Text(
            'Your answers so far will not be saved. Are you sure you want to leave?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Going'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Exit'),
            ),
          ],
        ),
      ).then((exit) {
        if (exit == true && mounted) Navigator.of(context).maybePop();
      });
    } else {
      _advanceTimer?.cancel();
      _controller.back();
    }
  }

  void _submit() {
    if (!_controller.isComplete) return;
    setState(() => _submitting = true);
    Navigator.of(context).pushReplacement(
      SmoothPageRoute(
        builder: (_) => AiProcessingScreen(controller: _controller),
      ),
    );
  }

  Widget _buildBody() {
    final area = _controller.area;
    switch (area) {
      case ScreeningArea.personal:
        return KeyedSubtree(
          key: const ValueKey('personal-step'),
          child: PersonalInfoStep(
            controller: _controller,
            onValidChanged: (_) => setState(() {}),
          ),
        );
      case ScreeningArea.lifestyle:
        final index = _controller.questionIndex;
        final question = lifestyleQuestions[index];
        return KeyedSubtree(
          key: ValueKey('lifestyle-$index'),
          child: LifestyleQuestionView(
            question: question,
            number: index + 1,
            total: lifestyleQuestions.length,
            value: _controller.lifestyle[question.field],
            onChanged: (v) => _controller.setLifestyle(question.field, v),
            onSelectChoice: _onSelect,
          ),
        );
      case ScreeningArea.phq:
      case ScreeningArea.gad:
      case ScreeningArea.pss:
      case ScreeningArea.who:
        final index = _controller.questionIndex;
        final item = _controller.currentQuestion!;
        return KeyedSubtree(
          key: ValueKey('${area.name}-$index'),
          child: OneQuestionScreen(
            category: _categoryLabel(area),
            question: item,
            number: index + 1,
            total: _controller.currentStepItems,
            selectedValue: _controller.currentAnswer,
            onSelect: _onSelect,
            safetyNote: area == ScreeningArea.phq && index == 8
                ? _safetyNote
                : null,
          ),
        );
      case ScreeningArea.review:
        return KeyedSubtree(
          key: const ValueKey('review-step'),
          child: ReviewStep(
            controller: _controller,
            onEdit: _controller.jumpToStep,
          ),
        );
    }
  }

  String _categoryLabel(ScreeningArea area) {
    switch (area) {
      case ScreeningArea.phq:
        return 'PHQ-9';
      case ScreeningArea.gad:
        return 'GAD-7';
      case ScreeningArea.pss:
        return 'PSS';
      case ScreeningArea.who:
        return 'WHO-5';
      default:
        return 'Screening';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildProgressHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.lg,
                  AppSpacing.page,
                  AppSpacing.xl,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: _buildBody(),
                ),
              ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _handleBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                tooltip: 'Back',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerLow,
                  foregroundColor: scheme.onSurface,
                  minimumSize: const Size(44, 44),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _controller.stepLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _controller.areaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_controller.answeredCount}/${_controller.totalQuestions} answered',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _controller.progress,
              minHeight: 6,
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isReview = _controller.area == ScreeningArea.review;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        child: isReview
            ? AppButton(
                label: 'Submit Assessment',
                icon: Icons.fact_check_outlined,
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
              )
            : Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _controller.canContinue
                          ? _controller.next
                          : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
