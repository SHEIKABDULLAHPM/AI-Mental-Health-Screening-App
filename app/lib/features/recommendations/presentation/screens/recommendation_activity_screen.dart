import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/recommendations/data/recommendation.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Lightweight activity player for recommendation activities.
///
/// Navigated to from the recommendation details screen when the user taps
/// "Start activity". Displays the activity title, description, duration,
/// and a timer with start/pause/complete controls.
///
/// On completion, records a COMPLETED interaction for the recommendation.
class RecommendationActivityScreen extends StatefulWidget {
  const RecommendationActivityScreen({
    super.key,
    required this.recommendationId,
    required this.title,
    required this.description,
    this.category,
    this.duration,
    this.difficulty,
  });

  final String recommendationId;
  final String title;
  final String description;
  final String? category;
  final String? duration;
  final String? difficulty;

  @override
  State<RecommendationActivityScreen> createState() =>
      _RecommendationActivityScreenState();
}

class _RecommendationActivityScreenState
    extends State<RecommendationActivityScreen> {
  Timer? _timer;
  bool _running = false;
  bool _completed = false;
  int _elapsedSeconds = 0;
  int _totalSeconds = 0;

  @override
  void initState() {
    super.initState();
    _totalSeconds = _parseDurationSeconds(widget.duration);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _parseDurationSeconds(String? duration) {
    if (duration == null || duration.isEmpty) return 300; // default 5 min
    final lower = duration.toLowerCase();
    // Parse "5 min", "10 min", "15 min", "60 min"
    final match = RegExp(r'(\d+)\s*min').firstMatch(lower);
    if (match != null) {
      return (int.tryParse(match.group(1)!) ?? 5) * 60;
    }
    return 300;
  }

  double get _progress =>
      _totalSeconds == 0 ? 0 : (_elapsedSeconds / _totalSeconds).clamp(0.0, 1.0);

  String get _remaining {
    final left = _totalSeconds - _elapsedSeconds;
    final minutes = (left ~/ 60).toString().padLeft(2, '0');
    final seconds = (left % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSeconds++);
        if (_elapsedSeconds >= _totalSeconds) {
          _complete();
        }
      });
    } else {
      _timer?.cancel();
    }
  }

  void _complete() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _completed = true;
    });

    // Record COMPLETED interaction
    final ctrl = context.read<RecommendationController>();
    ctrl.recordInteraction(widget.recommendationId, 'COMPLETED');

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Activity complete — well done!')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = widget.category != null
        ? parseCategory(widget.category!)
        : null;

    return FeatureScaffold(
      title: widget.title,
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // ── Category badge ──
                    if (cat != null) ...[
                      Text(
                        cat.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],

                    // ── Title ──
                    Text(
                      widget.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // ── Description ──
                    Text(
                      widget.description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),

                    // ── Meta chips ──
                    if (widget.duration != null ||
                        widget.difficulty != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        alignment: WrapAlignment.center,
                        children: [
                          if (widget.duration != null)
                            _MetaChip(
                              icon: Icons.schedule_rounded,
                              text: widget.duration!,
                            ),
                          if (widget.difficulty != null)
                            _MetaChip(
                              icon: Icons.signal_cellular_alt_rounded,
                              text: widget.difficulty!,
                            ),
                        ],
                      ),
                    ],

                    const Spacer(),

                    // ── Timer ring ──
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: CircularProgressIndicator(
                              value: _completed ? 1 : _progress,
                              strokeWidth: 12,
                              strokeCap: StrokeCap.round,
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _completed ? 'Done' : _remaining,
                                style:
                                    theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _running
                                    ? 'In progress'
                                    : _completed
                                        ? 'Great job'
                                        : 'Ready when you are',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // ── Controls ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Reset',
                          iconSize: 28,
                          onPressed: _running
                              ? null
                              : () {
                                  setState(() {
                                    _elapsedSeconds = 0;
                                    _completed = false;
                                  });
                                },
                          icon: const Icon(Icons.replay_rounded),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        SizedBox(
                          width: 88,
                          height: 88,
                          child: _completed
                              ? IconButton.filled(
                                  tooltip: 'Activity complete',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        theme.colorScheme.tertiary,
                                  ),
                                  iconSize: 36,
                                  onPressed: () {
                                    // Return to recommendation details
                                    if (context.canPop()) {
                                      context.pop();
                                    } else {
                                      context.go('/recommendations');
                                    }
                                  },
                                  icon: const Icon(Icons.check_rounded),
                                )
                              : IconButton.filled(
                                  tooltip:
                                      _running ? 'Pause' : 'Start',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        theme.colorScheme.primary,
                                  ),
                                  iconSize: 36,
                                  onPressed: _toggle,
                                  icon: Icon(
                                    _running
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        const IconButton.filledTonal(
                          tooltip: 'Volume',
                          iconSize: 28,
                          onPressed: null,
                          icon: Icon(Icons.volume_up_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(text),
      labelStyle: theme.textTheme.labelMedium,
    );
  }
}
