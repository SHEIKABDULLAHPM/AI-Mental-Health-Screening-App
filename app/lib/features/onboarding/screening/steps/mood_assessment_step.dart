import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/camera_emotion_mapping.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_result.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/camera_mood_screen.dart';
import 'package:mindease/features/onboarding/screening/screening_controller.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';

/// Unified onboarding mood assessment step.
///
/// Reuses the Mood Check-In scale ([kMoods]) and emotion tags
/// ([kMoodEmotions]) as the single source of truth — no forked mood lists.
/// The self-reported current mood is the primary signal and the only required
/// field; everything else is optional supporting context. When previous
/// check-in history exists it is shown for context instead of asking
/// redundant questions.
class MoodAssessmentStep extends StatelessWidget {
  const MoodAssessmentStep({super.key, required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HistoryBanner(controller: controller),
            Text(
              'How are you feeling right now?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'There are no wrong answers. Your current mood helps personalize '
              'your wellness profile.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _MoodGrid(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Which emotion fits best? (optional)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _EmotionChips(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            _IntensitySection(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            _CameraSection(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            _FrequencySection(controller: controller),
            const SizedBox(height: AppSpacing.md),
            _ChangeSection(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            _ReflectionField(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _HistoryBanner extends StatelessWidget {
  const _HistoryBanner({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final h = controller.moodHistory;
    if (h.loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Checking your previous check-ins…')),
          ],
        ),
      );
    }
    if (h.error != null) {
      // Non-blocking: the user can still complete a manual mood step.
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(
          'We couldn\u2019t load your previous check-ins, so let\u2019s start fresh below.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    if (!h.loaded || !h.hasHistory) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(
          'This looks like your first check-in — welcome.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    final lastMood = h.recent.isNotEmpty
        ? h.recent.first['mood'] as String?
        : h.mostCommonMood;
    final label = lastMood != null ? moodById(lastMood).label : null;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppSectionCard(
        icon: Icons.history_rounded,
        iconColor: theme.colorScheme.tertiary,
        title: 'Welcome back',
        subtitle: label != null
            ? 'Last time you felt $label. ${h.trendDescription}'
            : h.trendDescription.isNotEmpty
                ? h.trendDescription
                : null,
        children: const [],
      ),
    );
  }
}

class _MoodGrid extends StatelessWidget {
  const _MoodGrid({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.mood.currentMoodId;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final mood in kMoods)
          _MoodChoice(
            mood: mood,
            selected: selected == mood.id,
            onTap: () => controller.setMoodId(mood.id),
          ),
      ],
    );
  }
}

class _MoodChoice extends StatelessWidget {
  const _MoodChoice({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final Mood mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected
              ? mood.color.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? mood.color : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mood.icon, color: mood.color, size: 30),
            const SizedBox(height: 6),
            Text(
              mood.label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmotionChips extends StatelessWidget {
  const _EmotionChips({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.mood.emotion;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final emotion in kMoodEmotions)
          ChoiceChip(
            label: Text(emotion),
            selected: selected == emotion,
            onSelected: (_) => controller.setMoodEmotion(
              selected == emotion ? null : emotion,
            ),
          ),
      ],
    );
  }
}

class _IntensitySection extends StatelessWidget {
  const _IntensitySection({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'How strong is this feeling? (optional)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${controller.mood.intensity}/10',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: controller.mood.intensity.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: '${controller.mood.intensity}',
          onChanged: (v) => controller.setMoodIntensity(v.round()),
        ),
      ],
    );
  }
}

/// Optional camera supporting signal, reusing the existing `/mood-camera`
/// screen (live preview, face detection, quality gates, temporal stabilization,
/// user confirmation) instead of a second implementation.
///
/// The camera screen returns a stable, user-confirmed [CameraMoodResult] or
/// null (skipped / denied / backed out). A null result is not an error: the
/// flow continues with the self-reported mood, which always stays primary.
class _CameraSection extends StatelessWidget {
  const _CameraSection({required this.controller});

  final ScreeningController controller;

  Future<void> _openCamera(BuildContext context) async {
    final result = await context.push<CameraMoodResult>('/mood-camera');
    if (result != null) {
      controller.setCameraResult(result);
      // Suggest — never force — the camera-mapped tag as the emotion default.
      if ((controller.mood.emotion ?? '').isEmpty) {
        final tag = mapCanonicalToTag(result.emotion);
        if (tag != null) controller.setMoodEmotion(tag);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cam = controller.mood.cameraResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Camera check (optional)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (cam == null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openCamera(context),
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('Scan my expression'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your selection above stays primary — the camera is only '
            'supporting evidence. You can skip this entirely.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else
          _CameraResultCard(
            controller: controller,
            result: cam,
            onRetake: () => _openCamera(context),
            onRemove: () => controller.setCameraResult(null),
          ),
      ],
    );
  }
}

/// The three separate concepts, side by side: user-selected mood (primary),
/// stable camera emotion (supporting), and their deterministic relationship.
class _CameraResultCard extends StatelessWidget {
  const _CameraResultCard({
    required this.controller,
    required this.result,
    required this.onRetake,
    required this.onRemove,
  });

  final ScreeningController controller;
  final CameraMoodResult result;
  final VoidCallback onRetake;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userMoodId = controller.mood.currentMoodId;
    final agreement = userMoodId == null
        ? CameraAgreement.noSignal
        : cameraAgreement(
            userMoodId: userMoodId,
            cameraEmotion: result.emotion,
            cameraConfidence: result.confidence,
          );
    final interpretation = switch (agreement) {
      CameraAgreement.agree =>
        'Camera agrees with your selection — a strong supporting signal.',
      CameraAgreement.close =>
        'Camera signal is close to your selection.',
      CameraAgreement.differs =>
        'Camera signal differs from your selection — your selection stays primary.',
      CameraAgreement.noSignal =>
        'Camera result was unclear — continuing with your selection.',
    };
    return AppSectionCard(
      icon: Icons.videocam_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: 'Camera signal',
      // Display name only: confidence percentages and other internals stay
      // out of the normal user experience.
      subtitle: ferDisplayName(result.emotion),
      trailing: TextButton(
        onPressed: onRemove,
        child: const Text('Remove'),
      ),
      children: [
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            if (userMoodId != null) ...[
              Icon(
                moodById(userMoodId).icon,
                color: moodById(userMoodId).color,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'You: ${moodById(userMoodId).label}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Text(
                interpretation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retake scan'),
          ),
        ),
      ],
    );
  }
}

class _FrequencySection extends StatelessWidget {  const _FrequencySection({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How often have you felt this way lately? (optional)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in kMoodFrequencies)
              ChoiceChip(
                label: Text(option),
                selected: controller.mood.frequency == option,
                onSelected: (_) => controller.setMoodFrequency(
                  controller.mood.frequency == option ? null : option,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChangeSection extends StatelessWidget {
  const _ChangeSection({required this.controller});

  final ScreeningController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How has this changed recently? (optional)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in kMoodRecentChanges)
              ChoiceChip(
                label: Text(option),
                selected: controller.mood.recentChange == option,
                onSelected: (_) => controller.setMoodRecentChange(
                  controller.mood.recentChange == option ? null : option,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReflectionField extends StatefulWidget {
  const _ReflectionField({required this.controller});

  final ScreeningController controller;

  @override
  State<_ReflectionField> createState() => _ReflectionFieldState();
}

class _ReflectionFieldState extends State<_ReflectionField> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.mood.reflection);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Anything on your mind? (optional)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _text,
          maxLines: 3,
          maxLength: 500,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'A short reflection in your own words…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onChanged: widget.controller.setMoodReflection,
        ),
        Text(
          'Your words stay private to your account and help personalize your insight.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
