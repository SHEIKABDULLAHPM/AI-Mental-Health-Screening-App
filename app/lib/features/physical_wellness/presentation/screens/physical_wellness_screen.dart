import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/presentation/screens/ecg_screen.dart';
import 'package:mindease/features/physical_wellness/presentation/screens/heart_rate_monitor_screen.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_models.dart';
import 'package:mindease/features/physical_wellness/presentation/state/lifestyle_wellness_controller.dart';
import 'package:mindease/features/physical_wellness/presentation/state/physical_wellness_controller.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';
import 'package:mindease/shared/widgets/wellness_analysis_result_card.dart';

/// Formats a watch-reported distance for the dashboard stat tile.
///
/// The backend always stores metres. Short distances stay in metres because
/// "0.04 km" was both hard to read and ellipsised inside the tile; anything
/// from a kilometre up keeps the familiar "1.24 km" form.
String distanceLabel(double metres) {
  if (metres < 1000) return '${metres.toStringAsFixed(0)} m';
  return '${(metres / 1000).toStringAsFixed(2)} km';
}

/// Physical Wellness hub: the connected watch's readings, hydration, weight
/// and goals, weekly trends, Mind–Body patterns, and the device capability
/// registry. Every section distinguishes "no data" from "not supported" and
/// nothing is invented to fill a gap.
class PhysicalWellnessScreen extends StatefulWidget {
  const PhysicalWellnessScreen({super.key});

  @override
  State<PhysicalWellnessScreen> createState() => _PhysicalWellnessScreenState();
}

class _PhysicalWellnessScreenState extends State<PhysicalWellnessScreen>
    with WidgetsBindingObserver {
  /// Screen-scoped refresh: only ticks while this dashboard is open and the
  /// app is resumed. Steps on the band are cumulative, so this is what makes
  /// "today" keep advancing instead of freezing at the one startup sync.
  Timer? _autoSyncTimer;
  bool _resumed = true;
  bool _analyzingPhysical = false;
  MindeaseCombinedInsight? _mindBodyInsight;
  bool _loadingMindBody = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final physical = context.read<PhysicalWellnessController>();
      final lifestyle = context.read<LifestyleWellnessController>();
      lifestyle.init();
      physical.init().then((_) {
        if (!mounted) return;
        final deviceId = physical.device?.id ?? physical.today?.device?.id;
        if (deviceId != null) lifestyle.loadCapabilities(deviceId);
      });
      _loadMindBodyInsight();
    });
    _autoSyncTimer = Timer.periodic(
      PhysicalWellnessController.minAutoSyncInterval,
      (_) {
        if (!mounted || !_resumed) return;
        // Fire-and-forget: the controller guards re-entry and stays silent.
        context.read<PhysicalWellnessController>().syncIfStale();
      },
    );
  }

  Future<void> _loadMindBodyInsight() async {
    setState(() => _loadingMindBody = true);
    try {
      final res = await mindeaseApi.combinedInsight();
      if (!mounted) return;
      setState(() => _mindBodyInsight = res);
    } catch (_) {
      // Degrades silently
    } finally {
      if (mounted) setState(() => _loadingMindBody = false);
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _analyzePhysicalWellness() async {
    if (_analyzingPhysical) return;
    setState(() => _analyzingPhysical = true);
    try {
      final result = await wellnessAnalysisApi.analyzePhysicalWellness();
      if (!mounted) return;
      await showWellnessAnalysisSheet(
        context,
        WellnessAnalysisResult.physical(result),
      );
      // Sync recommendations to the recommendation controller
      if (mounted) {
        final recCtrl = context.read<RecommendationController>();
        recCtrl.loadRecommendations();
      }
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not run the physical analysis. Check your connection and try again.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _analyzePhysicalWellness,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzingPhysical = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding freezes the GATT session; on return, retry the durable
    // queue and refresh. The periodic read resumes only while the dashboard
    // is actually on screen.
    _resumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && mounted) {
      final physical = context.read<PhysicalWellnessController>();
      final deviceId = physical.device?.id ?? physical.today?.device?.id;
      physical.onForeground();
      physical.syncIfStale();
      context
          .read<LifestyleWellnessController>()
          .onForeground(deviceId: deviceId);
    }
  }

  Future<void> _refresh() async {
    final physical = context.read<PhysicalWellnessController>();
    final lifestyle = context.read<LifestyleWellnessController>();
    final deviceId = physical.device?.id ?? physical.today?.device?.id;
    await Future.wait([
      physical.onForeground(),
      lifestyle.refreshAll(deviceId: deviceId),
      _loadMindBodyInsight(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final physical = context.watch<PhysicalWellnessController>();
    final lifestyle = context.watch<LifestyleWellnessController>();
    final busy = (physical.loading && physical.today == null) ||
        (lifestyle.loading && !lifestyle.hasAnyData);

    if (busy) {
      return const FeatureScaffold(
        title: 'Physical Wellness',
        body: LoadingView(),
      );
    }

    final nothingAtAll = physical.today == null && !lifestyle.hasAnyData;
    if (nothingAtAll && (physical.error != null || lifestyle.error != null)) {
      return FeatureScaffold(
        title: 'Physical Wellness',
        body: ErrorStateView(
          title: 'Something went wrong',
          message: physical.error ?? lifestyle.error!,
          onRetry: _refresh,
        ),
      );
    }

    return FeatureScaffold(
      title: 'Physical Wellness',
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _Content(
          physical: physical,
          lifestyle: lifestyle,
          onRefresh: _refresh,
          onAnalyze: _analyzePhysicalWellness,
          analyzingPhysical: _analyzingPhysical,
          mindBodyInsight: _mindBodyInsight,
          loadingMindBody: _loadingMindBody,
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.physical,
    required this.lifestyle,
    required this.onRefresh,
    required this.onAnalyze,
    required this.analyzingPhysical,
    this.mindBodyInsight,
    this.loadingMindBody = false,
  });

  final PhysicalWellnessController physical;
  final LifestyleWellnessController lifestyle;
  final Future<void> Function() onRefresh;

  /// Runs the physical wellness analysis on the owning screen, which holds the
  /// navigation context and the busy state.
  final Future<void> Function() onAnalyze;
  final bool analyzingPhysical;
  final MindeaseCombinedInsight? mindBodyInsight;
  final bool loadingMindBody;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = physical.today;
    final deviceId = physical.device?.id ?? today?.device?.id;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        if (physical.offline || lifestyle.offline)
          _Banner(
            icon: Icons.cloud_off_rounded,
            color: theme.colorScheme.error,
            text: 'Offline — showing your last saved data. '
                'New changes will sync when you reconnect.',
          ),
        if (physical.notice != null)
          _Banner(
            icon: Icons.info_outline_rounded,
            color: theme.colorScheme.tertiary,
            text: physical.notice!,
            onDismiss: physical.clearNotice,
          ),
        if (lifestyle.notice != null)
          _Banner(
            icon: Icons.info_outline_rounded,
            color: theme.colorScheme.tertiary,
            text: lifestyle.notice!,
            onDismiss: lifestyle.clearNotice,
          ),
        if (lifestyle.lastSyncError != null)
          _Banner(
            icon: Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            text: lifestyle.lastSyncError!,
            onDismiss: lifestyle.clearNotice,
          ),
        if (lifestyle.pendingCount > 0)
          _Banner(
            icon: Icons.cloud_upload_outlined,
            color: theme.colorScheme.tertiary,
            text:
                '${lifestyle.pendingCount} change${lifestyle.pendingCount == 1 ? '' : 's'} '
                'waiting to sync. They are not saved on the server yet.',
          ),
        if (physical.offline ||
            lifestyle.offline ||
            physical.notice != null ||
            lifestyle.notice != null ||
            lifestyle.lastSyncError != null ||
            lifestyle.pendingCount > 0)
          const SizedBox(height: AppSpacing.md),
        _DeviceCard(physical: physical, onRefresh: onRefresh),
        const SizedBox(height: AppSpacing.md),
        _LiveMeasurementCard(lifestyle: lifestyle),
        if (today != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ActivityCard(today: today),
          const SizedBox(height: AppSpacing.md),
          _HeartRateCard(today: today),
          const SizedBox(height: AppSpacing.md),
          _SleepCard(block: today.sleep),
          const SizedBox(height: AppSpacing.md),
          _ExerciseCard(block: today.exercise),
        ],
        const SizedBox(height: AppSpacing.md),
        _HydrationCard(
          lifestyle: lifestyle,
          stale: lifestyle.staleSections.contains('hydration'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BodyCard(
          lifestyle: lifestyle,
          stale: lifestyle.staleSections.contains('body'),
        ),
        const SizedBox(height: AppSpacing.md),
        _GoalsCard(
          lifestyle: lifestyle,
          stale: lifestyle.staleSections.contains('goals'),
        ),
        const SizedBox(height: AppSpacing.md),
        _TrendsCard(
          lifestyle: lifestyle,
          stale: lifestyle.staleSections.contains('trends'),
        ),
        const SizedBox(height: AppSpacing.md),
        _PhysicalAnalysisCard(
          onAnalyze: onAnalyze,
          loading: analyzingPhysical,
        ),
        const SizedBox(height: AppSpacing.md),
        MindBodyInsightCard(
          lifestyle: lifestyle,
          stale: lifestyle.staleSections.contains('insights'),
          mindBodyInsight: mindBodyInsight,
          loadingMindBody: loadingMindBody,
        ),
        if (deviceId != null) ...[
          const SizedBox(height: AppSpacing.md),
          _CapabilitiesCard(
            lifestyle: lifestyle,
            deviceId: deviceId,
            stale: lifestyle.staleSections.contains('capabilities'),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── device

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.physical, required this.onRefresh});

  final PhysicalWellnessController physical;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registered = physical.device;
    final block = physical.today?.device;

    if (registered == null && block == null) {
      return AppSectionCard(
        icon: Icons.watch_rounded,
        iconColor: theme.colorScheme.tertiary,
        title: 'No watch connected',
        subtitle: 'Pair your FitPro watch to collect steps, sleep and heart '
            'rate. Hydration, weight and goals work without a watch.',
        children: [
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: physical.connecting
                ? 'Looking for your watch…'
                : 'Connect watch',
            icon: Icons.bluetooth_searching_rounded,
            loading: physical.connecting,
            onPressed: physical.connecting
                ? null
                : () =>
                    context.read<PhysicalWellnessController>().connectDevice(),
          ),
        ],
      );
    }

    final sync = physical.today?.sync;
    final battery = registered?.batteryLevel ?? block?.batteryLevel;
    final charging = registered?.charging ?? block?.charging;
    final lastSync =
        sync?.lastSyncedAt ?? registered?.lastSyncedAt ?? block?.lastSyncedAt;
    final subtitle = [
      if (battery != null)
        'Battery $battery%${charging == true ? ' · charging' : ''}',
      if (lastSync != null) 'Last sync ${_relative(lastSync)}',
      if (physical.pendingBatches > 0)
        '${physical.pendingBatches} batch${physical.pendingBatches == 1 ? '' : 'es'} waiting to upload',
    ].join(' · ');

    return AppSectionCard(
      icon: Icons.watch_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: registered?.displayName ?? block?.displayName ?? 'Watch',
      subtitle: subtitle.isEmpty ? null : subtitle,
      trailing: registered != null
          ? IconButton(
              tooltip: 'Forget watch',
              icon: const Icon(Icons.link_off_rounded),
              onPressed: () =>
                  context.read<PhysicalWellnessController>().forgetDevice(),
            )
          : null,
      children: [
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: physical.syncing ? 'Syncing…' : 'Sync now',
                icon: Icons.sync_rounded,
                variant: AppButtonVariant.outlined,
                loading: physical.syncing,
                onPressed: physical.syncing
                    ? null
                    : () async {
                        await context
                            .read<PhysicalWellnessController>()
                            .syncNow();
                        if (context.mounted) await onRefresh();
                      },
              ),
            ),
            if (registered != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Connect another',
                  icon: Icons.bluetooth_searching_rounded,
                  variant: AppButtonVariant.text,
                  onPressed: physical.connecting
                      ? null
                      : () => context
                          .read<PhysicalWellnessController>()
                          .connectDevice(),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── activity

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.today});

  final PhysicalToday today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = today.steps;
    final distance = today.distance;
    final calories = today.calories;
    final active = today.activeMinutes;

    return AppSectionCard(
      icon: Icons.directions_walk_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: "Today's activity",
      children: [
        const SizedBox(height: AppSpacing.sm),
        if (!steps.supported)
          const _UnsupportedText('This watch does not report step data.')
        else if (steps.value == null)
          const _NoDataText(
            'No steps synced yet. Wear the watch, then tap Sync now.',
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _grouped(steps.value!.toInt()),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              Text(
                'steps',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: !distance.supported
                    ? null
                    : distance.value == null
                        ? '—'
                        : distanceLabel(distance.value!),
                unsupportedHint: 'Not tracked',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.local_fire_department_rounded,
                label: 'Calories',
                value: !calories.supported
                    ? null
                    : calories.value == null
                        ? '—'
                        : '${calories.value!.toStringAsFixed(0)} kcal',
                unsupportedHint: 'Not tracked',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.timer_outlined,
                label: 'Active',
                value: !active.supported
                    ? null
                    : active.value == null
                        ? '—'
                        : '${active.value!.toStringAsFixed(0)} min',
                unsupportedHint: 'Not tracked',
              ),
            ),
          ],
        ),
        if (!active.supported) ...[
          const SizedBox(height: AppSpacing.sm),
          const _UnsupportedText(
            'Active minutes are unavailable when the watch only reports '
            'day totals, not per-chunk activity.',
          ),
        ],
      ],
    );
  }
}

/// Entry point for on-demand measurements. Rendered even when the synced
/// heart-rate block is unsupported, so the ECG state stays discoverable and
/// is explained rather than hidden.
class _LiveMeasurementCard extends StatelessWidget {
  const _LiveMeasurementCard({required this.lifestyle});

  final LifestyleWellnessController lifestyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ecg = lifestyle.capabilities?.find('ECG') ??
        lifestyle.capabilities?.find('ECG_WAVEFORM');
    final ecgSupported = ecg?.isSupported ?? false;

    return AppSectionCard(
      icon: Icons.sensors_rounded,
      iconColor: theme.colorScheme.error,
      title: 'Live measurements',
      subtitle: 'Take a reading now — separate from synced history',
      children: [
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppButton(
                    label: 'Heart rate',
                    icon: Icons.favorite_border_rounded,
                    variant: AppButtonVariant.outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HeartRateMonitorScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Start the optical sensor and watch the reading arrive.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppButton(
                    label: 'ECG',
                    icon: Icons.monitor_heart_outlined,
                    variant: AppButtonVariant.outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EcgScreen()),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ecgSupported
                        ? 'Capability reported by this watch.'
                        : 'Not available on this watch.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ecgSupported
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.today});

  final PhysicalToday today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final block = today.heartRate;
    if (!block.supported) return const SizedBox.shrink();
    final latest = block.latest;
    final resting = block.resting;
    final average = block.averageToday;
    final hasReadings = latest != null || resting != null || average != null;

    return AppSectionCard(
      icon: Icons.favorite_outline_rounded,
      iconColor: theme.colorScheme.error,
      title: 'Heart rate',
      subtitle: hasReadings ? null : 'No readings today yet',
      children: [
        if (hasReadings) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (latest != null)
                Expanded(
                  child: _StatTile(
                    icon: Icons.bolt_rounded,
                    label: 'Latest',
                    value: '${latest.toStringAsFixed(0)} bpm',
                  ),
                ),
              if (average != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatTile(
                    icon: Icons.trending_flat_rounded,
                    label: 'Average',
                    value: '${average.toStringAsFixed(0)} bpm',
                  ),
                ),
              ],
              if (resting != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatTile(
                    icon: Icons.hotel_outlined,
                    label: 'Resting',
                    value: '${resting.toStringAsFixed(0)} bpm',
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MetricLine(
                label: 'Blood oxygen (SpO2)',
                block: today.spo2,
                unsupportedHint: 'Not measured on this watch yet',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricLine(
                label: 'HRV',
                block: today.hrv,
                unsupportedHint: 'Not provided by this watch',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.label,
    required this.block,
    required this.unsupportedHint,
  });

  final String label;
  final MetricBlock block;
  final String unsupportedHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!block.supported)
            _UnsupportedText(unsupportedHint, compact: true)
          else if (block.value == null)
            const _NoDataText('No data')
          else
            Text(
              '${_compact(block.value!)} ${block.unit}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── sleep

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.block});

  final SleepBlock block;

  @override
  Widget build(BuildContext context) {
    if (!block.supported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final duration = block.durationMillis;
    return AppSectionCard(
      icon: Icons.nightlight_round,
      iconColor: const Color(0xFF5C6BC0),
      title: 'Sleep',
      subtitle: duration == null
          ? 'No sleep session recorded yet'
          : _duration(duration),
      children: [
        if (duration != null &&
            block.bedtime != null &&
            block.wakeTime != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_clock(block.bedtime!)} – ${_clock(block.wakeTime!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (duration != null && block.hasStages) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in block.stageMinutes.entries)
                _Chip(
                  label: '${_stageLabel(entry.key)} · ${entry.value} min',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _UnsupportedText(
            'Stage codes are shown exactly as the watch reports them '
            '(${block.stageSource ?? 'unknown source'}). Their mapping to '
            'light/deep/REM is not verified, so no stage is presented as one.',
          ),
        ],
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.block});

  final ExerciseBlock block;

  @override
  Widget build(BuildContext context) {
    if (!block.supported) return const SizedBox.shrink();
    final duration = block.durationMillis;
    return AppSectionCard(
      icon: Icons.directions_run_rounded,
      iconColor: const Color(0xFF26A69A),
      title: 'Exercise',
      subtitle: duration == null
          ? 'No exercise sessions today'
          : '${block.sessionCount} session${block.sessionCount == 1 ? '' : 's'} · ${_duration(duration)}',
    );
  }
}

// ─────────────────────────────────────────────────────────── hydration

class _HydrationCard extends StatelessWidget {
  const _HydrationCard({required this.lifestyle, required this.stale});

  final LifestyleWellnessController lifestyle;
  final bool stale;

  // Every mutation captures the messenger before awaiting. The saved notice
  // inserts a banner at the top of the list, which rebuilds the cards
  // positionally; their BuildContext can be unmounted by the time the request
  // finishes, so feedback must not depend on it.
  Future<void> _quickAdd(BuildContext context, int ml) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<LifestyleWellnessController>();
    final ok = await controller.addHydration(ml.toDouble(), unit: 'ml');
    _showLifestyleResult(messenger, controller, ok, 'Water logged.');
  }

  Future<void> _customAdd(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<LifestyleWellnessController>();
    final amount = await _askAmount(
      context,
      title: 'Log water',
      label: 'Amount (ml)',
      initial: 300,
      min: 1,
      max: 5000,
    );
    if (amount == null) return;
    final ok = await controller.addHydration(amount, unit: 'ml');
    _showLifestyleResult(messenger, controller, ok, 'Water logged.');
  }

  Future<void> _editEntry(
    BuildContext context,
    HydrationEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<LifestyleWellnessController>();
    final amount = await _askAmount(
      context,
      title: 'Edit entry',
      label: 'Amount (ml)',
      initial: entry.amountMl.round(),
      min: 1,
      max: 5000,
    );
    if (amount == null) return;
    final ok = await controller.updateHydration(
      entry.id,
      amount: amount,
      unit: 'ml',
      timestamp: entry.timestamp,
    );
    _showLifestyleResult(messenger, controller, ok, 'Entry updated.');
  }

  Future<void> _editTarget(
      BuildContext context, HydrationOverview value) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<LifestyleWellnessController>();
    final target = await _askAmount(
      context,
      title: 'Daily target',
      label: 'Target (ml)',
      initial: value.targetMl,
      min: 250,
      max: 10000,
    );
    if (target == null) return;
    final ok = await controller.setHydrationTarget(target.round());
    _showLifestyleResult(messenger, controller, ok, 'Target updated.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = lifestyle.hydration;

    return AppSectionCard(
      icon: Icons.water_drop_outlined,
      iconColor: const Color(0xFF039BE5),
      title: 'Hydration',
      subtitle: stale ? 'Showing saved data — could not refresh.' : null,
      trailing: value == null
          ? null
          : IconButton(
              tooltip: 'Edit daily target',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _editTarget(context, value),
            ),
      children: [
        if (value == null) ...[
          const _NoDataText('Hydration is unavailable right now.'),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Try again',
            variant: AppButtonVariant.outlined,
            onPressed: () =>
                context.read<LifestyleWellnessController>().loadHydration(),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _compact(value.today.totalMl),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ ${value.targetMl} ml',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: LinearProgressIndicator(
              value: value.progress,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value.today.hasEntries
                ? '${value.remainingMl == 0 ? 'Target reached' : '${value.remainingMl} ml to go'} · '
                    '${value.today.entryCount} entr${value.today.entryCount == 1 ? 'y' : 'ies'} logged'
                : 'Nothing logged today yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final ml in const [250, 500, 750])
                OutlinedButton(
                  onPressed:
                      lifestyle.saving ? null : () => _quickAdd(context, ml),
                  child: Text('+$ml ml'),
                ),
              OutlinedButton(
                onPressed: lifestyle.saving ? null : () => _customAdd(context),
                child: const Text('Custom'),
              ),
            ],
          ),
          if (value.today.entries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final entry in value.today.entries)
              _EntryRow(
                label: '${_compact(entry.amountMl)} ml',
                detail:
                    '${_clockOf(entry.timestamp)} · ${_sourceLabel(entry.source)}',
                onEdit:
                    lifestyle.saving ? null : () => _editEntry(context, entry),
                onDelete: lifestyle.saving
                    ? null
                    : () => context
                        .read<LifestyleWellnessController>()
                        .deleteHydration(entry.id),
              ),
          ],
          if (value.guidance != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _FinePrint(value.guidance!),
          ],
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────── body

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.lifestyle, required this.stale});

  final LifestyleWellnessController lifestyle;
  final bool stale;

  Future<void> _add(BuildContext context, BodySummary? value) async {
    // Captured before the save: the notice banner rebuilds the list and can
    // unmount this card's context while the request is in flight.
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<LifestyleWellnessController>();
    final result = await _askBodyMeasurement(context, value);
    if (result == null) return;
    final ok = await controller.addBodyMeasurement(
      weight: result.weight,
      height: result.height,
      weightUnit: result.weightUnit,
      heightUnit: result.heightUnit,
    );
    _showLifestyleResult(messenger, controller, ok, 'Measurement saved.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = lifestyle.body;

    return AppSectionCard(
      icon: Icons.monitor_weight_outlined,
      iconColor: const Color(0xFF8E24AA),
      title: 'Weight & BMI',
      subtitle: stale ? 'Showing saved data — could not refresh.' : null,
      children: [
        if (value == null) ...[
          const _NoDataText('No measurements available right now.'),
        ] else ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.scale_outlined,
                  label: 'Weight',
                  value: value.latest?.weightKg == null
                      ? '—'
                      : '${_compact(value.latest!.weightKg!)} kg',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  icon: Icons.height_rounded,
                  label: 'Height',
                  value: value.bmi?.heightCm != null
                      ? '${_compact(value.bmi!.heightCm!)} cm'
                      : value.latest?.heightCm != null
                          ? '${_compact(value.latest!.heightCm!)} cm'
                          : '—',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  icon: Icons.analytics_outlined,
                  label: 'BMI',
                  value: value.bmi == null ? '—' : _compact(value.bmi!.value),
                ),
              ),
            ],
          ),
          if (value.bmi != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${value.bmi!.label} · ${_bmiComposition(value.bmi!.weightKg, value.bmi!.heightCm)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _FinePrint(value.bmi!.disclaimer),
          ],
          if (value.trend.changeKg != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _weightTrendText(value.trend),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (value.additionalLimitations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            // The BMI disclaimer is already printed above and is filtered out
            // here, so the body-composition caveat is visible instead.
            for (final limitation in value.additionalLimitations.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _FinePrint(limitation),
              ),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Log weight or height',
          icon: Icons.add_rounded,
          variant: AppButtonVariant.outlined,
          loading: lifestyle.saving,
          onPressed: lifestyle.saving ? null : () => _add(context, value),
        ),
        if (value != null && value.history.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'History (${value.history.length})',
              style: theme.textTheme.bodyMedium,
            ),
            children: [
              for (final entry in value.history)
                _EntryRow(
                  label: [
                    if (entry.weightKg != null)
                      '${_compact(entry.weightKg!)} kg',
                    if (entry.heightCm != null)
                      '${_compact(entry.heightCm!)} cm',
                  ].join(' · '),
                  detail: '${entry.date} · ${_sourceLabel(entry.source)}',
                  onDelete: lifestyle.saving
                      ? null
                      : () => context
                          .read<LifestyleWellnessController>()
                          .deleteBodyMeasurement(entry.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────── goals

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.lifestyle, required this.stale});

  final LifestyleWellnessController lifestyle;
  final bool stale;

  Future<void> _editGoals(BuildContext context, GoalsOverview value) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<LifestyleWellnessController>();
    final result = await _askGoals(context, value);
    if (result == null) return;
    final ok = await controller.saveGoals(result);
    _showLifestyleResult(messenger, controller, ok, 'Goals updated.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = lifestyle.goals;

    if (value == null) {
      return AppSectionCard(
        icon: Icons.flag_outlined,
        iconColor: theme.colorScheme.primary,
        title: 'Goals',
        subtitle: stale ? 'Showing saved data — could not refresh.' : null,
        children: [
          const SizedBox(height: AppSpacing.sm),
          const _NoDataText('Goals are unavailable right now.'),
        ],
      );
    }

    return AppSectionCard(
      icon: Icons.flag_outlined,
      iconColor: theme.colorScheme.primary,
      title: 'Goals',
      subtitle: value.customized
          ? 'Your targets'
          : 'No targets chosen yet — progress stays blank until you set them.',
      trailing: IconButton(
        tooltip: 'Edit goals',
        icon: const Icon(Icons.edit_outlined),
        onPressed: lifestyle.saving ? null : () => _editGoals(context, value),
      ),
      children: [
        const SizedBox(height: AppSpacing.sm),
        for (final item in value.progress) GoalRow(item: item),
        if (!value.goals.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final entry in value.streaks.entries)
            if (entry.value.daysWithData > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '${_metricLabel(entry.key)} streak: '
                  '${entry.value.currentStreak} day${entry.value.currentStreak == 1 ? '' : 's'} '
                  '(best ${entry.value.longestStreak})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: value.customized ? 'Edit goals' : 'Set goals',
          icon: Icons.tune_rounded,
          variant: AppButtonVariant.outlined,
          loading: lifestyle.saving,
          onPressed: lifestyle.saving ? null : () => _editGoals(context, value),
        ),
        if (value.guidance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _FinePrint(value.guidance.first),
        ],
      ],
    );
  }
}

class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.item});

  final GoalProgress item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = item.dataAvailable ? item.progress : null;
    final target = item.target;
    final current = item.current;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (target != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _Chip(
                        label: item.isAiTarget ? 'AI Target' : 'Custom Target',
                        compact: true,
                        icon: item.isAiTarget
                            ? Icons.auto_awesome
                            : Icons.person_outline,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                target == null
                    ? 'No target'
                    : !item.dataAvailable
                        ? 'No data'
                        : '${_compact(current ?? 0)} / $target ${item.unit}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: item.met == true
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: item.met == true ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: LinearProgressIndicator(
              // `dataAvailable == false` means "no record yet", not an
              // in-progress task. A null value would render an indeterminate,
              // perpetually running bar; show a static empty track instead.
              value: progress ?? 0,
              minHeight: 8,
            ),
          ),
          if (target == null || !item.dataAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.note ??
                    (target == null
                        ? 'Choose a target to track this.'
                        : 'No record for this period.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────── trends

class _TrendsCard extends StatelessWidget {
  const _TrendsCard({required this.lifestyle, required this.stale});

  final LifestyleWellnessController lifestyle;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = lifestyle.trends;

    return AppSectionCard(
      icon: Icons.insights_rounded,
      iconColor: theme.colorScheme.secondary,
      title: 'Weekly trends',
      subtitle: value == null
          ? (stale ? 'Showing saved data — could not refresh.' : null)
          : '${value.windowDays}-day window · gaps are left as gaps',
      children: [
        if (value == null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: _NoDataText('Trends are unavailable right now.'),
          )
        else ...[
          const SizedBox(height: AppSpacing.sm),
          if (!value.metrics.any((m) => m.hasData))
            const _NoDataText(
              'No trend data in this window yet. Log water or weight, or '
              'sync the watch to add daily activity.',
            ),
          for (final metric in value.metrics.take(6)) _TrendRow(metric: metric),
          const SizedBox(height: AppSpacing.sm),
          _FinePrint(
            value.coverageNotes.isEmpty
                ? 'Only recorded days are plotted; missing days are not zero-filled.'
                : value.coverageNotes.join(' '),
          ),
        ],
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.metric});

  final MetricTrend metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = metric.points;
    final maxValue = points.isEmpty
        ? 0.0
        : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final change = metric.changePercent;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                !metric.hasData
                    ? 'No data'
                    : '${_compact(metric.average ?? 0)} ${metric.unit} avg',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (metric.hasData)
            SizedBox(
              height: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Tooltip(
                          message:
                              '${point.date}: ${_compact(point.value)} ${metric.unit}',
                          child: Container(
                            height: maxValue <= 0
                                ? 4
                                : (8 + 20 * (point.value / maxValue)),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary
                                  .withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            [
              '${metric.daysWithData} of ${metric.windowDays} days',
              if (change != null)
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}% vs previous',
              if (metric.quality != null) _qualityLabel(metric.quality!),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── insights

class MindBodyInsightCard extends StatelessWidget {
  const MindBodyInsightCard({
    super.key,
    required this.lifestyle,
    required this.stale,
    this.mindBodyInsight,
    this.loadingMindBody = false,
  });

  final LifestyleWellnessController lifestyle;
  final bool stale;
  final MindeaseCombinedInsight? mindBodyInsight;
  final bool loadingMindBody;

  static String _coverageLine(MindeaseInsightCoverage coverage) {
    final nights = coverage.daysWithSleep == 1 ? 'night' : 'nights';
    return 'Last ${coverage.windowDays} days: '
        'activity ${coverage.daysWithActivity} · '
        'sleep ${coverage.daysWithSleep} $nights · '
        'hydration ${coverage.daysWithHydration} · '
        'mood ${coverage.moodCheckins}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = lifestyle.insights;
    final combined = mindBodyInsight;
    final hasNarrative = combined?.available == true &&
        combined?.narrative != null &&
        combined!.narrative!.trim().isNotEmpty;

    final subtitle = loadingMindBody
        ? 'Analyzing mind–body connection…'
        : hasNarrative
            ? '${combined.isAiWording ? 'AI-personalised' : 'Based on your data'} · descriptive, not diagnostic'
            : value == null
                ? (stale ? 'Showing saved data — could not refresh.' : null)
                : !value.sufficientData
                    ? 'Not enough recent data to describe a pattern'
                    : '${value.windowDays}-day window · descriptive, not diagnostic';

    return AppSectionCard(
      icon: Icons.psychology_alt_rounded,
      iconColor: AppColors.success,
      title: 'Mind–Body Insight',
      subtitle: subtitle,
      children: [
        if (loadingMindBody) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Analyzing mind–body correlations…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (hasNarrative) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _Chip(
                label: combined.isAiWording
                    ? 'AI Personalised'
                    : 'Correlation Analysis',
                icon: Icons.auto_awesome,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            combined.narrative!.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
          if (combined.suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final suggestion in combined.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (suggestion.description.isNotEmpty)
                            Text(
                              suggestion.description,
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
          ],
          if (combined.coverage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _FinePrint(_coverageLine(combined.coverage!)),
          ],
          if (combined.note != null && combined.note!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _FinePrint(combined.note!.trim()),
          ],
          if (value != null && value.insights.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Observed Patterns',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
        if (value == null && !hasNarrative && !loadingMindBody)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: _NoDataText(
              'Mind–body insights are unavailable right now. Track your mood and sync your physical wellness metrics to see correlations.',
            ),
          )
        else if (value != null) ...[
          const SizedBox(height: AppSpacing.sm),
          if (!value.sufficientData &&
              value.coverage != null &&
              !hasNarrative) ...[
            _FinePrint(
              'What we have in the last ${value.windowDays} days: '
              '${value.coverage!.daysWithActivity} day'
              '${value.coverage!.daysWithActivity == 1 ? '' : 's'} of activity, '
              '${value.coverage!.daysWithSleep} of sleep, '
              '${value.coverage!.daysWithHydration} of hydration, '
              '${value.coverage!.moodCheckins} check-in'
              '${value.coverage!.moodCheckins == 1 ? '' : 's'}. '
              'Patterns need at least three earlier days and two recent days '
              'of real records.',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final insight in value.insights) _InsightTile(insight: insight),
          if (value.recommendations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pattern Suggestions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final rec in value.recommendations)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rec.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _Chip(
                          label: rec.source == 'AI_SERVICE'
                              ? 'Personalised'
                              : 'Rule-based',
                          compact: true,
                        ),
                      ],
                    ),
                    Text(
                      rec.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (!value.aiEnhanced) ...[
              const SizedBox(height: AppSpacing.xs),
              const _FinePrint(
                'Personalised wording was unavailable this time; these '
                'suggestions come from the rule engine alone.',
              ),
            ],
          ],
          if (value.limitations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final note in value.limitations) _FinePrint(note),
          ],
          if (value.disclaimer.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _FinePrint(value.disclaimer),
          ],
        ],
      ],
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight});

  final PatternInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (insight.severity) {
      'ATTENTION' => theme.colorScheme.error,
      'POSITIVE' => theme.colorScheme.primary,
      _ => theme.colorScheme.tertiary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  insight.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                insight.confidence,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            insight.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (insight.evidence.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final evidence in insight.evidence)
              Text(
                '• ${_evidenceText(evidence)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── capabilities

class _CapabilitiesCard extends StatelessWidget {
  const _CapabilitiesCard({
    required this.lifestyle,
    required this.deviceId,
    required this.stale,
  });

  final LifestyleWellnessController lifestyle;
  final String deviceId;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = lifestyle.capabilities;
    final supported =
        value?.capabilities.where((c) => c.isSupported).toList() ??
            const <DeviceCapabilityInfo>[];
    final unsupported =
        value?.capabilities.where((c) => !c.isSupported).toList() ??
            const <DeviceCapabilityInfo>[];

    return AppSectionCard(
      icon: Icons.verified_outlined,
      iconColor: theme.colorScheme.tertiary,
      title: 'What this watch can measure',
      subtitle: value == null
          ? (stale ? 'Showing saved data — could not refresh.' : null)
          : 'What the FitPro protocol can measure on this watch. Verified '
              'means a real record arrived; the app cannot self-certify.',
      trailing: IconButton(
        tooltip: 'Refresh capabilities',
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => lifestyle.loadCapabilities(deviceId),
      ),
      children: [
        if (value == null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: _NoDataText('Capabilities are unavailable right now.'),
          )
        else ...[
          const SizedBox(height: AppSpacing.sm),
          if (supported.isEmpty)
            const _NoDataText('No metric was reported by the last sync.')
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in supported)
                  _Chip(
                    label:
                        '${item.label}${item.isVerified ? ' · verified' : ' · unverified'}',
                    icon: item.isVerified
                        ? Icons.verified_rounded
                        : Icons.help_outline_rounded,
                  ),
              ],
            ),
          if (unsupported.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Not available',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final item in unsupported)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.limitations != null)
                      Text(
                        item.limitations!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          for (final note in value.notes) ...[
            const SizedBox(height: AppSpacing.sm),
            _FinePrint(note),
          ],
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── pieces

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.unsupportedHint,
  });

  final IconData icon;
  final String label;

  /// Null value renders an explicit "not supported" state, never a fake zero.
  final String? value;
  final String? unsupportedHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value == null) {
      return _UnsupportedText(
        unsupportedHint ?? '$label not supported',
        compact: true,
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value!,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.label,
    required this.detail,
    this.onEdit,
    this.onDelete,
  });

  final String label;
  final String detail;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '  $detail',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.compact = false});

  final String label;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: compact ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: compact ? 12 : 14,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: (compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.bodySmall)
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedText extends StatelessWidget {
  const _UnsupportedText(this.text, {this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: compact ? 3 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
    );
  }
}

class _NoDataText extends StatelessWidget {
  const _NoDataText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _FinePrint extends StatelessWidget {
  const _FinePrint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.onDismiss,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            if (onDismiss != null)
              InkWell(
                onTap: onDismiss,
                child: Icon(Icons.close_rounded, size: 16, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────── dialogs

/// Immediate, in-place feedback for a hydration/body/goal write. The notice
/// banner lives at the top of a long list, so a user who just tapped "Save"
/// halfway down the screen would otherwise see nothing.
void _showLifestyleResult(
  ScaffoldMessengerState messenger,
  LifestyleWellnessController controller,
  bool ok,
  String success,
) {
  if (!messenger.mounted) return;
  final pending = controller.pendingCount > 0;
  final text = ok
      ? (controller.notice ?? success)
      : (controller.lastSyncError ??
          (pending
              ? 'Saved on this phone and waiting to sync. It will retry when '
                  'you are back online.'
              : 'Could not save that change. Please try again.'));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<double?> _askAmount(
  BuildContext context, {
  required String title,
  required String label,
  required int initial,
  required int min,
  required int max,
}) {
  return showDialog<double>(
    context: context,
    builder: (context) => _AmountDialog(
      title: title,
      label: label,
      initial: initial,
      min: min,
      max: max,
    ),
  );
}

/// The controller lives in the dialog's own State so it is disposed only
/// after the exit animation has finished building. Disposing it right after
/// `showDialog` returns makes the still-animating TextField use a disposed
/// controller, which surfaced as an error whenever an edit was saved.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.min,
    required this.max,
  });

  final String title;
  final String label;
  final int initial;
  final int min;
  final int max;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed < widget.min || parsed > widget.max) {
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: '${widget.min}–${widget.max}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _BodyInput {
  const _BodyInput(
      {this.weight, this.height, this.weightUnit, this.heightUnit});

  final double? weight;
  final double? height;
  final String? weightUnit;
  final String? heightUnit;
}

Future<_BodyInput?> _askBodyMeasurement(
  BuildContext context,
  BodySummary? value,
) {
  return showDialog<_BodyInput>(
    context: context,
    builder: (context) => _BodyMeasurementDialog(value: value),
  );
}

class _BodyMeasurementDialog extends StatefulWidget {
  const _BodyMeasurementDialog({required this.value});

  final BodySummary? value;

  @override
  State<_BodyMeasurementDialog> createState() => _BodyMeasurementDialogState();
}

class _BodyMeasurementDialogState extends State<_BodyMeasurementDialog> {
  late final TextEditingController _weightController = TextEditingController(
    text: widget.value?.latest?.weightKg?._trimmed() ?? '',
  );
  late final TextEditingController _heightController = TextEditingController(
    text: widget.value?.bmi?.heightCm?._trimmed() ?? '',
  );
  late String _weightUnit = widget.value?.weightUnit ?? 'kg';
  late String _heightUnit = widget.value?.heightUnit ?? 'cm';

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _save() {
    final weight = double.tryParse(_weightController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    if (weight == null && height == null) return;
    if (weight != null && (weight <= 0 || weight > 500)) return;
    if (height != null && (height <= 0 || height > 300)) return;
    Navigator.of(context).pop(
      _BodyInput(
        weight: weight,
        height: height,
        weightUnit: weight == null ? null : _weightUnit,
        heightUnit: height == null ? null : _heightUnit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log measurement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Weight'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DropdownButton<String>(
                  value: _weightUnit,
                  items: const [
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'lb', child: Text('lb')),
                  ],
                  onChanged: (unit) =>
                      setState(() => _weightUnit = unit ?? _weightUnit),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Height'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DropdownButton<String>(
                  value: _heightUnit,
                  items: const [
                    DropdownMenuItem(value: 'cm', child: Text('cm')),
                    DropdownMenuItem(value: 'ft', child: Text('ft')),
                  ],
                  onChanged: (unit) =>
                      setState(() => _heightUnit = unit ?? _heightUnit),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _FinePrint(
              'BMI uses only these two values. Body-fat percentage and '
              'muscle mass are not asked for because no verified source '
              'provides them.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<GoalTargets?> _askGoals(BuildContext context, GoalsOverview value) {
  return showDialog<GoalTargets>(
    context: context,
    builder: (context) => _GoalsDialog(value: value),
  );
}

class _GoalsDialog extends StatefulWidget {
  const _GoalsDialog({required this.value});

  final GoalsOverview value;

  @override
  State<_GoalsDialog> createState() => _GoalsDialogState();
}

class _GoalsDialogState extends State<_GoalsDialog> {
  late final TextEditingController _steps =
      _controller(widget.value.goals.dailySteps);
  late final TextEditingController _active =
      _controller(widget.value.goals.dailyActiveMinutes);
  late final TextEditingController _workout =
      _controller(widget.value.goals.weeklyWorkoutMinutes);
  late final TextEditingController _sleep =
      _controller(widget.value.goals.dailySleepMinutes);
  late final TextEditingController _water =
      _controller(widget.value.goals.dailyHydrationMl);

  TextEditingController _controller(int? initial) =>
      TextEditingController(text: initial?.toString() ?? '');

  @override
  void dispose() {
    for (final c in [_steps, _active, _workout, _sleep, _water]) {
      c.dispose();
    }
    super.dispose();
  }

  void _useSuggested() {
    final defaults = widget.value.suggestedDefaults;
    setState(() {
      _steps.text = defaults.dailySteps?.toString() ?? '';
      _active.text = defaults.dailyActiveMinutes?.toString() ?? '';
      _workout.text = defaults.weeklyWorkoutMinutes?.toString() ?? '';
      _sleep.text = defaults.dailySleepMinutes?.toString() ?? '';
      _water.text = defaults.dailyHydrationMl?.toString() ?? '';
    });
  }

  void _save() {
    int? parse(TextEditingController c) {
      final text = c.text.trim();
      if (text.isEmpty) return null;
      return int.tryParse(text);
    }

    Navigator.of(context).pop(
      GoalTargets(
        dailySteps: parse(_steps),
        dailyActiveMinutes: parse(_active),
        weeklyWorkoutMinutes: parse(_workout),
        dailySleepMinutes: parse(_sleep),
        dailyHydrationMl: parse(_water),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your goals'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FinePrint(
              'Leave a field empty to remove that goal. Empty is not a '
              'default — progress stays blank until you choose a target.',
            ),
            const SizedBox(height: AppSpacing.md),
            _NumberField(controller: _steps, label: 'Daily steps'),
            _NumberField(controller: _active, label: 'Daily active minutes'),
            _NumberField(controller: _workout, label: 'Weekly workout minutes'),
            _NumberField(controller: _sleep, label: 'Nightly sleep minutes'),
            _NumberField(controller: _water, label: 'Daily water (ml)'),
            TextButton.icon(
              onPressed: _useSuggested,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Use suggested starting points'),
            ),
            const _FinePrint(
              'Suggested values are general starting points, not medical '
              'advice. Adjust them with a clinician if needed.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────── helpers

String _grouped(int value) => value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );

String _compact(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _duration(int millis) {
  final minutes = (millis ~/ 60000).clamp(0, 100000);
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return '${hours}h ${rest.toString().padLeft(2, '0')}m';
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _clockOf(DateTime time) => _clock(time);

String _relative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _stageLabel(String code) {
  final match = RegExp(r'^RAW_(\d+)$').firstMatch(code);
  if (match != null) return 'Stage ${match.group(1)} (raw)';
  return code;
}

String _sourceLabel(String source) => switch (source) {
      'USER_ENTERED' => 'you',
      'DEVICE_MEASURED' => 'watch',
      'MANUAL_ENTRY' => 'manual',
      _ => source.toLowerCase().replaceAll('_', ' '),
    };

String _metricLabel(String metric) => switch (metric) {
      'hydration' => 'Hydration',
      'steps' => 'Steps',
      'sleep' => 'Sleep',
      'workoutMinutes' => 'Workout',
      'activeMinutes' => 'Active minutes',
      _ => metric,
    };

String _qualityLabel(String quality) => switch (quality) {
      'USER_ENTERED' => 'user-entered',
      'DEVICE_MEASURED' => 'device-measured',
      'MANUAL_ENTRY' => 'manual',
      _ => quality.toLowerCase().replaceAll('_', ' '),
    };

String _bmiComposition(double? weightKg, double? heightCm) {
  final parts = [
    if (weightKg != null) '${_compact(weightKg)} kg',
    if (heightCm != null) '${_compact(heightCm)} cm',
  ];
  return parts.isEmpty ? 'limited screening measure' : parts.join(' · ');
}

String _weightTrendText(WeightTrend trend) {
  final change = trend.changeKg!;
  final direction = change == 0
      ? 'unchanged'
      : change < 0
          ? '${_compact(change.abs())} kg down'
          : '${_compact(change)} kg up';
  return '$direction since the previous measurement '
      '(${trend.daysWithData} day${trend.daysWithData == 1 ? '' : 's'} of data '
      'in ${trend.windowDays}).';
}

String _evidenceText(InsightEvidence evidence) {
  final unit = evidence.unit ?? '';
  final current = evidence.current == null
      ? '—'
      : '${_compact(evidence.current!)} $unit'.trim();
  final baseline = evidence.baseline == null
      ? null
      : '${_compact(evidence.baseline!)} $unit'.trim();
  final comparison = evidence.comparison.replaceAll('_', ' ');
  if (baseline == null) {
    return '${evidence.source}: $current ($comparison)';
  }
  return '${evidence.source}: $baseline → $current ($comparison)';
}

extension on double {
  String _trimmed() {
    if (this == roundToDouble()) return toStringAsFixed(0);
    return toStringAsFixed(1);
  }
}



class _PhysicalAnalysisCard extends StatelessWidget {
  const _PhysicalAnalysisCard({required this.onAnalyze, this.loading = false});

  final VoidCallback onAnalyze;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      icon: Icons.monitor_heart_outlined,
      iconColor: theme.colorScheme.secondary,
      title: 'Physical Wellness',
      subtitle: 'Analyze your physical wellbeing',
      children: [
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Get a real-time physical wellness analysis using your latest wearable data.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: loading ? null : onAnalyze,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(loading ? 'Analyzing…' : 'Analyze Physical Wellness'),
          ),
        ),
        if (loading) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Analyzing your wearable metrics and health trends with AI...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
