import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/physical_wellness/data/wearable_gateway.dart';
import 'package:mindease/features/physical_wellness/presentation/state/physical_wellness_controller.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Narrow seam between the screen and the wearable pipeline so the UI can be
/// tested without a platform channel, while production still goes through
/// [PhysicalWellnessController] and its durable sync queue.
abstract class LiveHeartRateSession {
  Future<String?> start();
  Future<bool> stop();
  Stream<LiveHeartRateSample> get samples;
  Future<int?> save(List<LiveHeartRateSample> samples);
}

/// Production adapter: every call is the controller's own contract (start
/// command → band measurement → durable persistence), not a parallel path.
class ControllerLiveHeartRateSession implements LiveHeartRateSession {
  ControllerLiveHeartRateSession(this._controller);

  final PhysicalWellnessController _controller;

  @override
  Future<String?> start() => _controller.startHeartRateMonitor();

  @override
  Future<bool> stop() => _controller.stopHeartRateMonitor();

  @override
  Stream<LiveHeartRateSample> get samples => _controller.liveHeartRate;

  @override
  Future<int?> save(List<LiveHeartRateSample> samples) =>
      _controller.saveLiveHeartRate(samples);
}

/// Live heart-rate measurement.
///
/// Start sends the verified FitPro measurement-on command (general group
/// `0x18`) and renders **only** the samples the band actually emits. A silent
/// sensor shows "waiting for a reading"; it never displays an invented or
/// interpolated value, and stopping persists the collected samples through the
/// same durable queue a history sync uses.
class HeartRateMonitorScreen extends StatefulWidget {
  const HeartRateMonitorScreen({super.key, this.session});

  /// Injected in tests; resolved from [PhysicalWellnessController] otherwise.
  final LiveHeartRateSession? session;

  @override
  State<HeartRateMonitorScreen> createState() => _HeartRateMonitorScreenState();
}

class _HeartRateMonitorScreenState extends State<HeartRateMonitorScreen> {
  LiveHeartRateSession? _session;
  StreamSubscription<LiveHeartRateSample>? _subscription;
  final List<LiveHeartRateSample> _samples = [];
  bool _running = false;
  bool _starting = false;
  String? _status;
  String? _savedNote;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= widget.session ??
        ControllerLiveHeartRateSession(
          context.read<PhysicalWellnessController>(),
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // Leaving the screen must not leave the optical sensor (and battery)
    // running remotely; fire-and-forget because dispose cannot await.
    if (_running) unawaited(_session?.stop());
    super.dispose();
  }

  Future<void> _start() async {
    final session = _session;
    if (session == null || _starting || _running) return;
    setState(() {
      _starting = true;
      _status = null;
      _savedNote = null;
    });
    final error = await session.start();
    if (!mounted) return;
    if (error != null) {
      // A failed (re)start must not wipe the session the user is still
      // looking at: the previous readings stay on screen with the error.
      setState(() {
        _starting = false;
        _status = error;
      });
      return;
    }
    // Only a confirmed start begins a new session, so clear here rather than
    // optimistically before the band acknowledged the command.
    setState(_samples.clear);
    _subscription = session.samples.listen(
      _onSample,
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _status = 'Live stream error: $e');
      },
    );
    setState(() {
      _starting = false;
      _running = true;
    });
  }

  void _onSample(LiveHeartRateSample sample) {
    if (!mounted) return;
    setState(() {
      _samples.add(sample);
      // Keep the in-memory window bounded; persistence uses the same list.
      if (_samples.length > 600) _samples.removeAt(0);
    });
  }

  Future<void> _stop() async {
    final session = _session;
    if (session == null || !_running) return;
    final subscription = _subscription;
    _subscription = null;
    // Do not await cancellation: the hardware stop must not be blocked by a
    // stream teardown that may never acknowledge (or that is completed on a
    // different zone). The subscription is detached either way, so no late
    // samples reach the UI.
    unawaited(subscription?.cancel());
    setState(() => _running = false);
    await session.stop();
    final saved = await session.save(List.of(_samples));
    if (!mounted) return;
    setState(() {
      _savedNote = saved == null
          ? null
          : '$saved live reading${saved == 1 ? '' : 's'} queued for sync.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _samples.isEmpty ? null : _samples.last.bpm;
    final values = [for (final s in _samples) s.bpm];
    final min = values.isEmpty ? null : values.reduce(math.min);
    final max = values.isEmpty ? null : values.reduce(math.max);

    return FeatureScaffold(
      title: 'Heart rate monitor',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          AppSectionCard(
            icon: Icons.monitor_heart_outlined,
            iconColor: theme.colorScheme.error,
            title: 'Live measurement',
            subtitle: _running
                ? 'Measuring — keep the watch on your wrist'
                : 'Uses the watch\'s optical heart-rate sensor',
            children: [
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Column(
                  children: [
                    Text(
                      latest == null ? '—' : '$latest',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: latest == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                    Text(
                      latest == null ? 'bpm (no sample yet)' : 'bpm',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _running ? 'Stop' : 'Start',
                icon: _running
                    ? Icons.stop_circle_outlined
                    : Icons.favorite_border_rounded,
                loading: _starting,
                onPressed: _running ? _stop : _start,
              ),
              if (_status != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _status!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              if (_savedNote != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_savedNote!, style: theme.textTheme.bodySmall),
              ],
              if (_running && _samples.isEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Waiting for the watch to report a beat. If nothing arrives, '
                  'check that the watch is worn snugly and its optical sensor '
                  'is against your skin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppSectionCard(
            icon: Icons.show_chart_rounded,
            title: 'Session',
            subtitle: _samples.isEmpty
                ? 'No samples yet'
                : '${_samples.length} samples'
                    '${min == null ? '' : ' · $min–$max bpm'}',
            children: [
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 140,
                child: _samples.isEmpty
                    ? Center(
                        child: Text(
                          'The chart fills only with readings reported by the '
                          'watch.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : CustomPaint(
                        painter: _HeartRateSparklinePainter(
                          values: values,
                          color: theme.colorScheme.error,
                          gridColor: theme.colorScheme.outlineVariant,
                        ),
                        size: Size.infinite,
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Readings come from a consumer wearable and are not a medical '
                'measurement. Stop and seek advice if you feel unwell.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Minimal sparkline: draws the reported samples in order, no smoothing or
/// interpolation, so the line never implies data that was not measured.
class _HeartRateSparklinePainter extends CustomPainter {
  _HeartRateSparklinePainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<int> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final dy = size.height * i / 4;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
    }
    if (values.length < 2) return;

    final minV = values.reduce(math.min).toDouble();
    final maxV = values.reduce(math.max).toDouble();
    final span = math.max(1.0, maxV - minV);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final dx = size.width * i / (values.length - 1);
      // 10% padding keeps the line inside the card.
      final norm = (values[i] - minV) / span;
      final dy = size.height * (0.9 - norm * 0.8);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HeartRateSparklinePainter oldDelegate) =>
      oldDelegate.values.length != values.length ||
      oldDelegate.values.lastOrNull != values.lastOrNull;
}
