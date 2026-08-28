import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/presentation/widgets/mood_widgets.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Mood result screen shown after mood analysis and confirmation.
/// Displays the AI analysis result with mood, emotion, sentiment,
/// confidence, trend, guidance, and reflection prompt.
class MoodResultScreen extends StatelessWidget {
  const MoodResultScreen({
    super.key,
    required this.moodId,
    this.analysisResult,
    this.emotion,
    this.note,
    this.intensity,
  });

  final String moodId;
  final Map<String, dynamic>? analysisResult;
  final String? emotion;
  final String? note;
  final int? intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = moodById(moodId);
    final analysis = analysisResult;
    final trend = analysis?['trend'] as Map<String, dynamic>?;
    final guidance = analysis?['guidance'] as Map<String, dynamic>?;
    final safety = analysis?['safety'] as Map<String, dynamic>?;
    final reflection = analysis?['reflection'] as Map<String, dynamic>?;
    final safetyFlag = safety?['flag'] as bool? ?? false;
    final safetyLevel = safety?['level'] as String? ?? 'none';
    final fusedEmotion = analysis?['fused_emotion'] as String?;
    final confidence = (analysis?['confidence'] as num?)?.toDouble();
    final needsConfirmation = analysis?['needs_confirmation'] as bool? ?? false;
    final sentiment = analysis?['text_analysis']?['sentiment'] as String?;

    return FeatureScaffold(
      title: 'Mood Result',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          // ── Safety alert ──
          if (safetyFlag) ...[
            _SafetyAlert(
              level: safetyLevel,
              message: safety?['message'] as String?,
              resources: safety?['resources'] as Map<String, dynamic>?,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Mood result card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  MoodDot(mood: mood, size: 72),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Feeling ${mood.label.toLowerCase()}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (fusedEmotion != null && fusedEmotion != 'unknown') ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        fusedEmotion,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (confidence != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (sentiment != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sentiment: $sentiment',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (needsConfirmation) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'The AI analysis differs from your selection. Your chosen mood has been saved.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Intensity ──
          if (intensity != null) ...[
            const SizedBox(height: AppSpacing.md),
            IntensityBar(intensity: intensity!),
          ],

          // ── Trend ──
          if (trend != null && trend['direction'] != 'unknown') ...[
            const SizedBox(height: AppSpacing.md),
            _TrendCard(trend: trend),
          ],

          // ── Guidance ──
          if (guidance != null) ...[
            const SizedBox(height: AppSpacing.md),
            _GuidanceCard(guidance: guidance),
          ],

          // ── Reflection ──
          if (reflection != null && reflection['text'] != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ReflectionCard(prompt: reflection['text'] as String),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── Actions ──
          AppButton(
            label: 'Done',
            icon: Icons.check_rounded,
            onPressed: () {
              // Navigate back to mood home, clearing the stack
              context.go('/mood');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.push('/mood-trends'),
              child: const Text('View Trends'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyAlert extends StatelessWidget {
  const _SafetyAlert({
    required this.level,
    this.message,
    this.resources,
  });

  final String level;
  final String? message;
  final Map<String, dynamic>? resources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCrisis = level == 'crisis';

    return Card(
      color: isCrisis
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCrisis ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  color: isCrisis
                      ? theme.colorScheme.error
                      : theme.colorScheme.tertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isCrisis ? 'Safety Notice' : 'Support Available',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCrisis
                        ? theme.colorScheme.error
                        : theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isCrisis
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
            if (resources != null) ...[
              const SizedBox(height: AppSpacing.sm),
              if (resources!['helpline'] != null)
                Text(
                  resources!['helpline']!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCrisis
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              if (resources!['crisisText'] != null)
                Text(
                  resources!['crisisText']!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCrisis
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              if (resources!['message'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  resources!['message']!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isCrisis
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});

  final Map<String, dynamic> trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = trend['direction'] as String? ?? 'unknown';
    final description = trend['description'] as String? ?? '';

    final (icon, color) = switch (direction) {
      'improving' => (Icons.trending_up_rounded, Colors.green),
      'declining' => (Icons.trending_down_rounded, theme.colorScheme.error),
      'fluctuating' => (Icons.show_chart_rounded, theme.colorScheme.tertiary),
      'stable' => (Icons.trending_flat_rounded, theme.colorScheme.primary),
      _ => (Icons.help_outline_rounded, theme.colorScheme.onSurfaceVariant),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mood Trend: ${direction[0].toUpperCase()}${direction.substring(1)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
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
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({required this.guidance});

  final Map<String, dynamic> guidance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = guidance['message'] as String? ?? '';
    final actions = (guidance['actions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final safetyFlag = guidance['safety_flag'] as bool? ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 20,
                  color: safetyFlag
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  safetyFlag ? 'Safety Guidance' : 'Suggested for today',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: safetyFlag
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ...actions.map((action) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _actionIcon(action['type'] as String?),
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                action['title'] ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                action['description'] ?? '',
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
                  ),),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _actionIcon(String? type) => switch (type) {
        'breathing' => Icons.air_rounded,
        'movement' => Icons.directions_walk_rounded,
        'journaling' => Icons.edit_note_rounded,
        'reflection' => Icons.psychology_rounded,
        'relax' => Icons.spa_rounded,
        'break' => Icons.coffee_rounded,
        'continue' => Icons.thumb_up_alt_rounded,
        'routine' => Icons.calendar_today_rounded,
        _ => Icons.circle_outlined,
      };
}

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.question_answer_rounded,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Reflection',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              prompt,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
