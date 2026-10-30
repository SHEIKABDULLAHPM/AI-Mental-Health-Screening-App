import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/constants/moods.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/widgets/mood_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Read-only detail view for a single mood entry.
/// Shows mood face, emotion, note, date/time, and AI analysis breakdown.
class MoodDetailScreen extends StatefulWidget {
  const MoodDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<MoodDetailScreen> createState() => _MoodDetailScreenState();
}

class _MoodDetailScreenState extends State<MoodDetailScreen> {
  MoodEntry? _fetched;
  bool _fetching = false;
  bool _fetchStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch once from API if the entry is not in the local cache
    // (e.g. deep-link). Guarded by _fetchStarted so rebuilds never loop.
    if (!_fetchStarted) {
      final controller =
          Provider.of<MoodController>(context, listen: false);
      final cached = controller.entries
          .where((e) => e.id == widget.entryId)
          .firstOrNull;
      if (cached == null && !controller.loading) {
        _fetchStarted = true;
        _fetching = true;
        controller.loadEntry(widget.entryId).then((result) {
          if (!mounted) return;
          setState(() {
            _fetched = result;
            _fetching = false;
          });
        });
      } else {
        _fetchStarted = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Provider.of<MoodController>(context);
    MoodEntry? entry = controller.entries
            .where((e) => e.id == widget.entryId)
            .firstOrNull ??
        _fetched;

    return FeatureScaffold(
      title: 'Mood entry',
      actions: [
        IconButton(
          tooltip: 'Delete',
          onPressed: entry != null ? () => _confirmDelete(context) : null,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      body: _fetching
          ? const LoadingView()
          : entry == null
              ? const ErrorStateView(
                  title: 'Entry not found',
                  message:
                      'This mood entry could not be found or was deleted.',
                )
              : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                _MoodHeader(entry: entry),
                const SizedBox(height: AppSpacing.lg),
                if (entry.note != null && entry.note!.isNotEmpty) ...[
                  Text(
                    'Note',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        entry.note!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _InfoRow(
                  icon: Icons.schedule_rounded,
                  label: 'Recorded on',
                  value:
                      '${entry.dayLabel} at ${entry.timeLabel}',
                ),
                if (entry.source != null)
                  _InfoRow(
                    icon: _sourceIcon(entry.source!),
                    label: 'Source',
                    value: _sourceLabel(entry.source!),
                  ),
                if (entry.analysisStatus != null)
                  _InfoRow(
                    icon: Icons.analytics_outlined,
                    label: 'Analysis',
                    value: entry.analysisStatus!,
                  ),
                if (entry.intensity != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  IntensityBar(intensity: entry.intensity!),
                ],
                if (entry.hasAiData) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _AIBreakdown(entry: entry),
                ],
              ],
            ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final controller = Provider.of<MoodController>(context, listen: false);
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete mood entry?'),
        content: const Text(
          'This mood entry will be permanently removed. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await controller.deleteMood(widget.entryId);
              if (!context.mounted) return;
              if (controller.error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(controller.error!)),
                );
                return;
              }
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  static IconData _sourceIcon(String source) => switch (source) {
        'CAMERA' => Icons.camera_alt_rounded,
        'TEXT' => Icons.edit_note_rounded,
        'MULTIMODAL' => Icons.auto_awesome_rounded,
        _ => Icons.pan_tool_rounded,
      };

  static String _sourceLabel(String source) => switch (source) {
        'CAMERA' => 'Camera facial analysis',
        'TEXT' => 'Text emotion analysis',
        'MULTIMODAL' => 'Camera + text analysis',
        _ => 'Manual entry',
      };
}

class _MoodHeader extends StatelessWidget {
  const _MoodHeader({required this.entry});

  final MoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = moodById(entry.moodId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            MoodDot(mood: mood, size: 64),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feeling ${mood.label.toLowerCase()}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (entry.emotion != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.emotion!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (entry.confidence != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'AI confidence: ${(entry.confidence! * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _AIBreakdown extends StatelessWidget {
  const _AIBreakdown({required this.entry});

  final MoodEntry entry;

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
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'AI Analysis',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (entry.aiSuggestedMood != null)
              _AINotification(
                label: 'Suggested mood',
                value: entry.aiSuggestedMood!.replaceAll('_', ' '),
              ),
            ...entry.aiObservations.map(
              (obs) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: _AINotification(
                  label: _obsSourceLabel(obs.source),
                  value: _obsValue(obs),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _obsSourceLabel(String source) => switch (source) {
        'TEXT' => 'Text analysis',
        'CAMERA' => 'Camera analysis',
        _ => 'AI observation',
      };

  static String _obsValue(AiObservation obs) {
    final parts = <String>[
      '${obs.emotion} (${(obs.confidence * 100).toStringAsFixed(0)}%)',
    ];
    if (obs.sentiment != null) {
      parts.add('sentiment: ${obs.sentiment}');
    }
    return parts.join(' · ');
  }
}

class _AINotification extends StatelessWidget {
  const _AINotification({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
