import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/camera_emotion_mapping.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/camera_mood_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/widgets/mood_widgets.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_snackbar.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

class RecordMoodScreen extends StatefulWidget {
  const RecordMoodScreen({super.key, this.cameraResult});

  final CameraMoodResult? cameraResult;

  @override
  State<RecordMoodScreen> createState() => _RecordMoodScreenState();
}

class _RecordMoodScreenState extends State<RecordMoodScreen> {
  final TextEditingController _note = TextEditingController();
  Mood? _selected;
  String? _emotion;
  bool _saving = false;
  bool _useAi = true;
  double _intensity = 5;

  /// Stable idempotency key for the emotion-event POST: one per screen
  /// instance, so retries/double-taps replay the same event instead of
  /// duplicating it (server dedupes by key).
  late final String _eventKey = 'cam-${DateTime.now().millisecondsSinceEpoch}'
      '-${widget.cameraResult?.framesAnalyzed ?? 0}';

  @override
  void initState() {
    super.initState();
    if (widget.cameraResult != null) {
      _useAi = true;
      final camEmotion = widget.cameraResult!.emotion.toLowerCase();
      _emotion = _mapCameraEmotionToLabel(camEmotion);
    }
  }

  /// Map the canonical emotion id to a user-facing tag.
  /// Versioned in [kCameraEmotionMappingVersion]; the canonical class is
  /// always preserved in the camera observation payload. Null only for
  /// 'unknown' (no pre-fill).
  String? _mapCameraEmotionToLabel(String emotion) =>
      mapCanonicalToTag(emotion);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_selected == null) {
      AppSnackbar.show(context, 'Pick how you are feeling first.');
      return;
    }
    setState(() => _saving = true);
    final controller = Provider.of<MoodController>(context, listen: false);

    final hasCamera = widget.cameraResult != null;
    final hasText = _note.text.isNotEmpty;
    final shouldAnalyze = _useAi && (hasCamera || hasText);

    Map<String, dynamic>? analysis;

    if (shouldAnalyze) {
      Map<String, dynamic>? cameraObs;
      if (hasCamera) {
        cameraObs = widget.cameraResult!.toMap();
      }

      analysis = await controller.analyzeMood(
        mood: _selected!.id,
        emotion: _emotion,
        note: hasText ? _note.text : null,
        cameraObservation: cameraObs,
      );

      if (!mounted) return;

      if (analysis != null) {
        // Backend returns snake_case keys via @JsonProperty
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

        String source;
        if (sourcesUsed.contains('TEXT') && sourcesUsed.contains('CAMERA')) {
          source = 'MULTIMODAL';
        } else if (sourcesUsed.contains('CAMERA')) {
          source = 'CAMERA';
        } else if (sourcesUsed.contains('TEXT')) {
          source = 'TEXT';
        } else {
          source = 'MANUAL';
        }

        // Persist the AI's actual read, not the fused result: the user's own
        // selection is already stored as the mood, and fusing now echoes it back,
        // so `fused_mood` would lose the AI signal entirely.
        final suggestedMood = analysis['ai_suggested_mood'] as String?;

        await controller.recordMood(
          moodId: _selected!.id,
          emotion: _emotion,
          note: hasText ? _note.text : null,
          source: source,
          confidence: confidence,
          aiSuggestedMood: suggestedMood,
          aiObservations: observations,
          intensity: _intensity.round(),
        );
      } else {
        await controller.recordMood(
          moodId: _selected!.id,
          emotion: _emotion,
          note: hasText ? _note.text : null,
          source: hasCamera ? 'CAMERA' : 'MANUAL',
          intensity: _intensity.round(),
        );
      }
    } else {
      // Fusion unavailable or not requested. The check-in is still saved with
      // the note and, when the device produced one, the local camera result —
      // no AI mood is invented.
      await controller.recordMood(
        moodId: _selected!.id,
        emotion: _emotion,
        note: _note.text.isEmpty ? null : _note.text,
        source: hasCamera ? 'CAMERA' : 'MANUAL',
        aiObservations: hasCamera
            ? [
                {
                  'source': 'CAMERA',
                  'emotion': widget.cameraResult!.emotion,
                  'confidence': widget.cameraResult!.confidence,
                  'suggestedMood': null,
                  'modelVersion': widget.cameraResult!.modelVersion,
                },
              ]
            : null,
        intensity: _intensity.round(),
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);

    // The controller swallows persistence errors into `error` — never
    // navigate to the success screen when the write actually failed.
    if (controller.error != null) {
      AppSnackbar.show(context, controller.error!);
      return;
    }

    // Persist the confirmed camera observation as an immutable emotion event.
    // Independent store from the mood record above (no double-write of the
    // mood itself); best-effort so event ingestion can never block or break
    // the check-in flow.
    if (hasCamera) {
      await controller.recordEmotionEvent(
        widget.cameraResult!.toEventMap(
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          idempotencyKey: _eventKey,
        ),
      );
    }

    if (!mounted) return;
    context.go('/mood-result', extra: {
      'moodId': _selected!.id,
      'analysisResult': analysis,
      'emotion': _emotion,
      'note': hasText ? _note.text : null,
      'intensity': _intensity.round(),
    },);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FeatureScaffold(
      title: 'How are you feeling?',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick the face that best matches your mood right now.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.spaceBetween,
              children: [
                for (final mood in kMoods)
                  MoodFaceButton(
                    mood: mood,
                    selected: _selected?.id == mood.id,
                    onTap: () => setState(() => _selected = mood),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Add an emotion (optional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final emotion in kMoodEmotions)
                  ChoiceChip(
                    label: Text(emotion),
                    selected: _emotion == emotion,
                    onSelected: (_) =>
                        setState(() => _emotion = emotion),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            IntensityBar(
              intensity: _intensity.round(),
              showLabel: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  'Mild',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _intensity,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _intensity.round().toString(),
                    onChanged: (v) => setState(() => _intensity = v),
                  ),
                ),
                Text(
                  'Intense',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _note,
              label: 'Note (optional)',
              hint: 'What affected your mood?',
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'AI Mood Analysis',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                widget.cameraResult != null
                    ? 'Camera facial analysis + text emotion insights'
                    : 'Analyze your note for emotion and sentiment insights',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _useAi,
              onChanged: (v) => setState(() => _useAi = v),
            ),
            if (widget.cameraResult != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Card(
                color: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.camera_alt_rounded,
                        size: 18,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          // Plain-language only: raw confidence percentages and
                          // other model internals are never user-facing.
                          'Camera reading added',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Consumer<MoodController>(
              builder: (context, moodCtrl, _) {
                if (moodCtrl.analyzing) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text('Analyzing your mood...'),
                      ],
                    ),
                  );
                }
                if (moodCtrl.analysisResult != null) {
                  final result = moodCtrl.analysisResult!;
                  final fusedMood = result['fused_mood'] as String?;
                  final aiSuggestedMood = result['ai_suggested_mood'] as String?;
                  final confidence =
                      (result['confidence'] as num?)?.toDouble();
                  final sources =
                      (result['sources_used'] as List?)?.cast<String>() ?? [];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Card(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'AI Analysis',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (fusedMood != null)
                              Text(
                                'Saved mood: ${fusedMood.replaceAll('_', ' ')}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            if (aiSuggestedMood != null &&
                                aiSuggestedMood != fusedMood)
                              Text(
                                'AI read: ${aiSuggestedMood.replaceAll('_', ' ')} '
                                '(your selection is kept)',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (confidence != null)
                              Text(
                                'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (sources.isNotEmpty)
                              Text(
                                'Sources: ${sources.join(', ')}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            AppButton(
              label: 'Save Mood',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
