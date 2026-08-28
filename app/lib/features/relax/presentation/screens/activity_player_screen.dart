import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/relax/data/relax_activity.dart';
import 'package:mindease/features/relax/presentation/state/relax_controller.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Relaxation activity player with start / pause / complete states.
class ActivityPlayerScreen extends StatefulWidget {
  const ActivityPlayerScreen({super.key, required this.activityId});

  final String activityId;

  @override
  State<ActivityPlayerScreen> createState() => _ActivityPlayerScreenState();
}

class _ActivityPlayerScreenState extends State<ActivityPlayerScreen> {
  Timer? _timer;
  bool _running = false;
  bool _completed = false;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RelaxController>().loadById(widget.activityId);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _progress {
    final a = context.read<RelaxController>().currentActivity;
    if (a == null) return 0;
    final total = a.duration.inSeconds;
    return total == 0 ? 0 : (_elapsedSeconds / total).clamp(0.0, 1.0);
  }

  String get _remaining {
    final a = context.read<RelaxController>().currentActivity;
    if (a == null) return '--:--';
    final left = a.duration.inSeconds - _elapsedSeconds;
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
        if (_elapsedSeconds >= (context.read<RelaxController>().currentActivity?.duration.inSeconds ?? 0)) {
          _complete();
        }
      });
    } else {
      _timer?.cancel();
    }
  }

  void _complete() {
    _timer?.cancel();
    final ctrl = context.read<RelaxController>();
    ctrl.completeActivity(widget.activityId);
    setState(() {
      _running = false;
      _completed = true;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Session complete — well done!')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<RelaxController>();
    final activity = ctrl.currentActivity;

    return FeatureScaffold(
      title: activity?.title ?? 'Activity',
      body: ctrl.loading || activity == null
          ? const LoadingView()
          : LayoutBuilder(
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
                  Text(
                    activity.category.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    activity.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    activity.description,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
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
                            backgroundColor:
                                theme.colorScheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _completed ? 'Done' : _remaining,
                              style: theme.textTheme.displaySmall?.copyWith(
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
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
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
                                tooltip: 'Session complete',
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.tertiary,
                                ),
                                iconSize: 36,
                                onPressed: _complete,
                                icon: const Icon(Icons.check_rounded),
                              )
                            : IconButton.filled(
                                tooltip: _running ? 'Pause' : 'Start',
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
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
                  Text(
                    'Audio preview — full sessions arrive in a future update.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
