import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/api/mindease_api.dart';
import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_loading_dots.dart';
import 'package:mindease/shared/widgets/app_logo.dart';

/// Shows the assessment being finalized by the AI service while it analyzes
/// the submitted responses. Polls the server-side analysis job and hands over
/// to the wellness profile when it completes, or offers a retry on failure.
class AiProcessingScreen extends StatefulWidget {
  const AiProcessingScreen({super.key});

  @override
  State<AiProcessingScreen> createState() => _AiProcessingScreenState();
}

class _AiProcessingScreenState extends State<AiProcessingScreen>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Analyzing your responses…',
    'Recognizing patterns…',
    'Creating your wellness profile…',
    'Preparing personalized insights…',
  ];

static const _jobStates = {
    'QUEUED',
    'PROCESSING',
    'COMPLETED',
    'FAILED',
    'RETRY_QUEUED',
  };

  late final AnimationController _pulse;
  late final MindeaseApi _api;
  Timer? _messageTimer;
  Timer? _pollTimer;
  int _messageIndex = 0;
  bool _completed = false;
  bool _retrying = false;
  bool _failed = false;
  bool _unknownJob = false;
  String? _jobId;
  int _unknownPolls = 0;

  /// Consecutive polls that returned a known non-terminal state. Bounded so
  /// a job stuck server-side surfaces the retry card instead of polling
  /// forever with no way out (90 polls x 2 s = ~3 min; real analyses finish
  /// in seconds and the server sweeper fails stale jobs at 5 min).
  int _pendingPolls = 0;
  static const _maxPendingPolls = 90;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _api = mindeaseApi;
    _jobId = ScreeningSession.aiJobId;

    _messageTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
      });
    });

    if (_jobId == null) {
      _showUnknownJob();
    } else {
      _poll();
    }
  }

  void _showUnknownJob() {
    // No job id to poll: never pretend the analysis succeeded.
    _messageTimer?.cancel();
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _unknownJob = true;
      _failed = true;
    });
  }

  Future<void> _poll() async {
    if (!mounted || _completed) return;
    _pollTimer?.cancel();
    final jobId = _jobId;
    if (jobId == null) return;

    final status = await _api.aiAnalysisStatus(jobId);
    if (!mounted || _completed) return;

    final state = status['status'] as String?;
    if (state == null) {
      // Unknown job id: keep polling briefly, then show an error so the user
      // can retry instead of silently navigating away.
      _unknownPolls += 1;
      _unknownJob = true;
      if (_unknownPolls > 5) {
        _showUnknownJob();
        return;
      }
      _schedulePoll();
      return;
    }

    if (state == 'COMPLETED') {
      _completeToProfile();
      return;
    }

    if (state == 'FAILED') {
      setState(() => _failed = true);
      return;
    }

    if (_jobStates.contains(state)) {
      _pendingPolls += 1;
      if (_pendingPolls > _maxPendingPolls) {
        // Still not terminal after minutes: stop polling and offer retry
        // instead of spinning indefinitely.
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() => _failed = true);
        return;
      }
      _schedulePoll();
    }
  }

  void _schedulePoll() {
    if (!mounted || _completed) return;
    _pollTimer = Timer(const Duration(seconds: 2), _poll);
  }

  Future<void> _completeToProfile() async {
    if (_completed) return;
    _completed = true;
    _messageTimer?.cancel();
    _pollTimer?.cancel();
    if (!mounted) return;
    context.go('/wellness-profile');
  }

  Future<void> _retry() async {
    final jobId = _jobId;
    if (jobId == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      await _api.retryAiAnalysis(jobId);
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _failed = false;
      });
      _pendingPolls = 0;
      _schedulePoll();
    } on Object {
      if (!mounted) return;
      setState(() => _retrying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to restart the analysis right now. '
              'Please try again in a moment.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _pollTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // Minimal exit: polling stops on dispose and the server-side job is
      // unaffected, so leaving can never lose or corrupt the analysis.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: CloseButton(
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                RepaintBoundary(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.25),
                                    AppColors.primary.withValues(alpha: 0.02),
                                  ],
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: AppColors.gradientStart,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 50,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: AppLogoMark(size: 88),
                              ),
                            ),
                            for (final phase in [0.0, 0.33, 0.66])
                              Builder(
                                builder: (context) {
                                  final progress =
                                      (_pulse.value + phase) % 1.0;
                                  return Transform.scale(
                                    scale: 1 + 0.6 * progress,
                                    child: Opacity(
                                      opacity: (1 - progress).clamp(0.0, 1.0),
                                      child: Container(
                                        width: 170,
                                        height: 170,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: Text(
                    _messages[_messageIndex],
                    key: ValueKey(_messageIndex),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_failed)
                  _FailedCard(
                    onRetry: _unknownJob || _retrying ? null : _retry,
                    unknown: _unknownJob,
                  )
                else
                  const Center(child: AppLoadingDots(size: 14)),
                const SizedBox(height: AppSpacing.xl),
                SafeArea(
                  top: false,
                  child: Center(
                    child: Text(
                      _failed
                          ? _unknownJob
                              ? 'We couldn’t find the analysis for this '
                                  'assessment. You can review your profile '
                                  'later.'
                              : 'We couldn’t complete the analysis this time. '
                                  'You can retry, or review your profile later.'
                          : 'Please keep the app open — this usually takes '
                              'a few seconds.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact inline card shown when the analysis job fails, offering a retry.
class _FailedCard extends StatelessWidget {
  const _FailedCard({this.onRetry, this.unknown = false});

  final VoidCallback? onRetry;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.refresh_rounded, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              unknown
                  ? 'Analysis unavailable.'
                  : 'Analysis paused — retry when you’re ready.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (!unknown)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
