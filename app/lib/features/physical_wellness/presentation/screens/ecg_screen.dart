import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/presentation/state/lifestyle_wellness_controller.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Capture seam for ECG-capable hardware.
///
/// Production ships **no** implementation: no verified FitPro ECG frame
/// sequence exists for this watch generation, so [EcgScreen] resolves support
/// from the server capability registry (which has no ECG metric) and shows an
/// explicit unsupported state. The seam exists for tests and for future
/// hardware whose capture path has actually been verified — it must never be
/// backed by synthesized samples.
abstract class EcgSession {
  /// Sends the start command. Returns null on success, or a message.
  Future<String?> start();

  Future<void> stop();

  /// Millivolt samples exactly as the hardware reported them.
  Stream<double> get samples;
}

/// ECG measurement screen.
///
/// The Start button is present but disabled unless the connected device has a
/// verified ECG capability. That is deliberate: showing a Start button that
/// silently draws an invented waveform would misrepresent a health signal.
class EcgScreen extends StatefulWidget {
  const EcgScreen({super.key, this.supportedOverride, this.session});

  /// Test hook; production resolves support from the capability registry.
  final bool? supportedOverride;

  /// Test hook; production passes null until a verified capture path exists.
  final EcgSession? session;

  @override
  State<EcgScreen> createState() => _EcgScreenState();
}

class _EcgScreenState extends State<EcgScreen> {
  StreamSubscription<double>? _subscription;
  final List<double> _samples = [];
  bool _running = false;
  bool _starting = false;
  String? _status;

  @override
  void dispose() {
    _subscription?.cancel();
    if (_running) unawaited(widget.session?.stop());
    super.dispose();
  }

  Future<void> _start() async {
    final session = widget.session;
    if (session == null || _starting || _running) return;
    setState(() {
      _starting = true;
      _status = null;
      _samples.clear();
    });
    final error = await session.start();
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _starting = false;
        _status = error;
      });
      return;
    }
    _subscription = session.samples.listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _samples.add(value);
          if (_samples.length > 2000) _samples.removeAt(0);
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _status = 'ECG stream error: $e');
      },
    );
    setState(() {
      _starting = false;
      _running = true;
    });
  }

  Future<void> _stop() async {
    final session = widget.session;
    if (session == null || !_running) return;
    final subscription = _subscription;
    _subscription = null;
    // Detach without awaiting: the sensor stop must not be blocked by stream
    // teardown, and no late samples should reach the trace after this point.
    unawaited(subscription?.cancel());
    setState(() => _running = false);
    await session.stop();
  }

  /// Support comes from the server's capability registry, never from a guess
  /// about the product name. The registry has no ECG metric for this watch, so
  /// the screen opens in its unsupported state on real hardware.
  bool _resolveSupported(BuildContext context) {
    if (widget.supportedOverride != null) return widget.supportedOverride!;
    try {
      final capabilities =
          context.watch<LifestyleWellnessController>().capabilities;
      final capability = _ecgCapability(capabilities);
      return capability?.isSupported ?? false;
    } on ProviderNotFoundException {
      return false;
    }
  }

  DeviceCapabilityInfo? _ecgCapability(CapabilityList? list) {
    if (list == null) return null;
    return list.find('ECG') ?? list.find('ECG_WAVEFORM');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = _resolveSupported(context);
    final session = widget.session;
    final captureAvailable = supported && session != null;
    final latest = _samples.isEmpty ? null : _samples.last;

    return FeatureScaffold(
      title: 'ECG',
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
            iconColor:
                supported ? theme.colorScheme.error : theme.colorScheme.outline,
            title: supported ? 'ECG capture' : 'ECG is not supported',
            subtitle: supported
                ? 'Single-lead rhythm trace from the watch'
                : 'This watch does not expose an ECG sensor to the app',
            children: [
              const SizedBox(height: AppSpacing.md),
              if (!supported) ...[
                Text(
                  'No ECG service or ECG command was found on the connected '
                  'watch during device discovery, and the capability registry '
                  'does not list ECG for this model. The heart-rate sensor is '
                  'available instead. No waveform is shown, because a made-up '
                  'trace would be a fabricated health reading.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Start',
                  icon: Icons.play_arrow_rounded,
                  onPressed: null,
                ),
              ] else if (!captureAvailable) ...[
                Text(
                  'This watch reports ECG support, but this app build has no '
                  'verified ECG capture path for its firmware yet. Nothing is '
                  'drawn rather than showing a simulated trace.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Start',
                  icon: Icons.play_arrow_rounded,
                  onPressed: null,
                ),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      Text(
                        latest == null
                            ? '—'
                            : '${latest.toStringAsFixed(2)} mV',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: latest == null
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                      Text(
                        latest == null ? 'no signal yet' : 'latest sample',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: _running ? 'Stop' : 'Start',
                  icon: _running
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded,
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
              ],
            ],
          ),
          if (supported && captureAvailable) ...[
            const SizedBox(height: AppSpacing.md),
            AppSectionCard(
              icon: Icons.show_chart_rounded,
              title: 'Trace',
              subtitle: _samples.isEmpty
                  ? 'No samples yet'
                  : '${_samples.length} samples',
              children: [
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 160,
                  child: _samples.length < 2
                      ? Center(
                          child: Text(
                            _running
                                ? 'Waiting for the watch to report a trace…'
                                : 'The trace fills only with samples the watch '
                                    'actually reports.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : CustomPaint(
                          painter: _EcgTracePainter(
                            values: _samples,
                            color: theme.colorScheme.error,
                            gridColor: theme.colorScheme.outlineVariant,
                          ),
                          size: Size.infinite,
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'A consumer single-lead signal, not a diagnostic ECG: it '
                  'uses no clinical electrode placement and must not be used '
                  'to detect or rule out a heart condition.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Plots reported millivolts in order with no smoothing or interpolation.
class _EcgTracePainter extends CustomPainter {
  _EcgTracePainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<double> values;
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
    for (var i = 0; i <= 8; i++) {
      final dx = size.width * i / 8;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
    }
    if (values.length < 2) return;

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = math.max(0.01, maxV - minV);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final dx = size.width * i / (values.length - 1);
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
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _EcgTracePainter oldDelegate) =>
      oldDelegate.values.length != values.length ||
      oldDelegate.values.lastOrNull != values.lastOrNull;
}
