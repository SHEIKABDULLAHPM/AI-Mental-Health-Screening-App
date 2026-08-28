import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/journal/data/journal_entry.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/shared/widgets/app_snackbar.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Journal entry detail with edit/delete, media display, and AI analysis slots.
class JournalEntryDetailsScreen extends StatefulWidget {
  const JournalEntryDetailsScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<JournalEntryDetailsScreen> createState() =>
      _JournalEntryDetailsScreenState();
}

class _JournalEntryDetailsScreenState extends State<JournalEntryDetailsScreen> {
  static const _aiPollInterval = Duration(seconds: 3);
  static const _maxAiPollAttempts = 20;
  Timer? _aiPollTimer;
  int _aiPollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _aiPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final controller = Provider.of<JournalController>(context, listen: false);
    await controller.loadEntry(widget.entryId);
    _maybeStartAiPoll();
  }

  /// Poll pending analysis without interrupting the reading experience.
  void _maybeStartAiPoll() {
    _aiPollTimer?.cancel();
    final controller = Provider.of<JournalController>(context, listen: false);
    final entry = controller.currentEntry;
    if (_isAnalysisPending(entry?.aiAnalysis)) {
      _aiPollAttempts = 0;
      _aiPollTimer = Timer.periodic(_aiPollInterval, (_) async {
        if (!mounted) {
          _aiPollTimer?.cancel();
          return;
        }
        await controller.loadEntry(widget.entryId, silently: true);
        final updated = controller.currentEntry;
        _aiPollAttempts++;
        if (!_isAnalysisPending(updated?.aiAnalysis) ||
            _aiPollAttempts >= _maxAiPollAttempts) {
          _aiPollTimer?.cancel();
        }
      });
    }
  }

  static bool _isAnalysisPending(AiAnalysisData? analysis) =>
      analysis?.status == 'NOT_REQUESTED' ||
      analysis?.isProcessing == true ||
      analysis?.isStale == true;

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry'),
        content: const Text(
          'This action cannot be undone. Are you sure you want to delete this journal entry?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final controller = Provider.of<JournalController>(context, listen: false);
      final success = await controller.deleteEntry(widget.entryId);
      if (success && mounted) {
        AppSnackbar.show(context, 'Entry deleted.');
        context.pop();
      } else if (mounted) {
        AppSnackbar.show(context, 'Failed to delete entry.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Provider.of<JournalController>(context);
    final entry = controller.currentEntry;
    final loading = controller.loading;

    return FeatureScaffold(
      title: 'Entry',
      actions: [
        if (entry != null) ...[
          IconButton(
            tooltip: 'Edit',
            onPressed: () => context.push('/journal/${entry.id}/edit'),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ],
      body: loading
          ? const LoadingView()
          : entry == null
              ? ErrorStateView(
                  title: 'Entry not found',
                  message: 'This entry could not be found.',
                  onRetry: () {
                    setState(() {});
                    _load();
                  },
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    // ── Title ──
                    Text(
                      entry.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // Wrap keeps long dates and emotion labels readable on small screens.
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _InfoChip(
                          icon: _typeIcon(entry.type),
                          label: entry.type.label,
                          color: theme.colorScheme.primary,
                        ),
                        _InfoChip(
                          icon: Icons.schedule_rounded,
                          label: '${entry.dateLabel} · ${entry.timeLabel}',
                        ),
                        if (entry.emotion != null)
                          _InfoChip(
                            icon: Icons.emoji_emotions_outlined,
                            label: entry.emotion!,
                            color: theme.colorScheme.tertiary,
                          ),
                      ],
                    ),
                    if (entry.updatedAt != null &&
                        entry.updatedAt!.difference(entry.date).inMinutes >
                            1) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Updated ${_formatRelativeTime(entry.updatedAt!)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),

                    // ── Content ──
                    if (entry.content.isNotEmpty)
                      Text(
                        entry.content,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.7,
                        ),
                      ),

                    // ── Image ──
                    if (entry.hasImage) ...[
                      const SizedBox(height: AppSpacing.lg),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: entry.imageUrl != null
                            ? Image.network(
                                entry.imageUrl!,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _MediaPlaceholder(
                                  icon: Icons.broken_image_rounded,
                                  label: 'Image could not be loaded',
                                  color: theme.colorScheme.error,
                                ),
                                loadingBuilder: (_, child, progress) =>
                                    progress == null
                                        ? child
                                        : Container(
                                            height: 200,
                                            width: double.infinity,
                                            color: theme
                                                .colorScheme.primaryContainer,
                                            child: const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          ),
                              )
                            : _MediaPlaceholder(
                                icon: Icons.image_rounded,
                                label: 'Image attachment',
                                color: theme.colorScheme.primary,
                              ),
                      ),
                    ],

                    // ── Audio ──
                    if (entry.hasAudio) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _AudioPlayerCard(entry: entry),
                    ],

                    // ── Video ──
                    if (entry.hasVideo) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _VideoPlayerCard(entry: entry),
                    ],

                    // ── AI Analysis ──
                    const SizedBox(height: AppSpacing.xl),
                    _AIAnalysisSection(
                      analysis: entry.aiAnalysis,
                      onRetry: () async {
                        final ctrl = Provider.of<JournalController>(context, listen: false);
                        await ctrl.retryAiAnalysis(entry.id);
                        _maybeStartAiPoll();
                      },
                    ),
                  ],
                ),
    );
  }

  static String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static IconData _typeIcon(JournalEntryType type) => switch (type) {
        JournalEntryType.text => Icons.notes_rounded,
        JournalEntryType.voice => Icons.mic_rounded,
        JournalEntryType.image => Icons.photo_rounded,
        JournalEntryType.video => Icons.videocam_rounded,
      };
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: effectiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPlayerCard extends StatefulWidget {
  const _AudioPlayerCard({required this.entry});

  final JournalEntry entry;

  @override
  State<_AudioPlayerCard> createState() => _AudioPlayerCardState();
}

class _AudioPlayerCardState extends State<_AudioPlayerCard> {
  late final AudioPlayer _player;
  bool _playing = false;
  bool _loaded = false;
  bool _loadError = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _playing = state.playing);
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }
    });
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    final url = widget.entry.audioUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _loadError = true);
      return;
    }
    try {
      await _player.setUrl(url);
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = true;
          _errorMessage = 'Could not load audio: ${e is Exception ? e.toString() : e}';
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _duration.inSeconds > 0
        ? _duration
        : Duration(seconds: widget.entry.audioDurationSeconds ?? 0);
    final progress =
        total.inSeconds > 0 ? _position.inSeconds / total.inSeconds : 0.0;
    final canPlay = widget.entry.audioUrl != null && _loaded && !_loadError;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _loadError
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _loadError ? Icons.error_outline_rounded : Icons.mic_rounded,
                    color: _loadError
                        ? theme.colorScheme.error
                        : theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice recording',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _loadError
                            ? (_errorMessage ?? 'Audio unavailable')
                            : '${_formatDuration(_position)} / ${_formatDuration(total)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _loadError
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  onPressed: canPlay ? _togglePlayback : null,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.tertiary,
                    foregroundColor: theme.colorScheme.onTertiary,
                  ),
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 24,
                  ),
                ),
              ],
            ),
            if (total.inSeconds > 0 && !_loadError) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        if (_position >= _duration && _duration.inSeconds > 0) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = true;
          _errorMessage = 'Playback failed. Try reloading the entry.';
          _playing = false;
        });
      }
    }
  }
}

class _VideoPlayerCard extends StatelessWidget {
  const _VideoPlayerCard({required this.entry});

  final JournalEntry entry;

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUrl = entry.videoUrl != null && entry.videoUrl!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video preview area
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasUrl ? Icons.play_circle_fill_rounded : Icons.videocam_rounded,
                      size: 56,
                      color: theme.colorScheme.secondary,
                    ),
                    if (!hasUrl) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Video attachment',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Video metadata
            Row(
              children: [
                Icon(
                  Icons.videocam_rounded,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Video recording',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (entry.videoDurationSeconds != null)
                  Text(
                    _formatDuration(entry.videoDurationSeconds),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (entry.videoSize != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _formatFileSize(entry.videoSize),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AIAnalysisSection extends StatelessWidget {
  const _AIAnalysisSection({required this.analysis, this.onRetry});

  final AiAnalysisData? analysis;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (analysis == null || analysis!.status == 'NOT_REQUESTED') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'AI analysis will start shortly…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (analysis!.isProcessing) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Analysing your entry…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (analysis!.hasFailed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'AI analysis could not be completed for this entry.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry analysis'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (analysis!.isStale) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Content has changed since the last analysis. The previous result is outdated.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Re-analyse'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // COMPLETED — show results
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            Text(
              'AI Analysis',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Summary card
        if (analysis!.summary != null && analysis!.summary!.isNotEmpty) ...[
          Card(
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.summarize_rounded,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      analysis!.summary!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        // Emotion + Sentiment
        if (analysis!.emotion != null) ...[
          _AILine(
            label: 'Emotion',
            value: analysis!.emotionConfidence != null
                ? '${analysis!.emotion!} (${(analysis!.emotionConfidence! * 100).round()}%)'
                : analysis!.emotion!,
          ),
        ],
        if (analysis!.sentiment != null) ...[
          _AILine(
            label: 'Sentiment',
            value: analysis!.sentimentConfidence != null
                ? '${analysis!.sentiment!} (${(analysis!.sentimentConfidence! * 100).round()}%)'
                : analysis!.sentiment!,
          ),
        ],
        if (analysis!.emotionalThemes != null &&
            analysis!.emotionalThemes!.isNotEmpty)
          _AILine(label: 'Themes', value: analysis!.emotionalThemes!),

        // Reflection prompt
        if (analysis!.reflectionPrompt != null &&
            analysis!.reflectionPrompt!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      analysis!.reflectionPrompt!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AILine extends StatelessWidget {
  const _AILine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
