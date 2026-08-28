import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/domain/emotion_classifier.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Result returned from the camera mood check-in.
class CameraMoodResult {
  const CameraMoodResult({
    required this.emotion,
    required this.confidence,
    required this.faceQuality,
    required this.framesAnalyzed,
    this.emotionScores = const {},
    this.valence = 0.0,
    this.arousal = 0.0,
  });

  final String emotion;
  final double confidence;
  final double faceQuality;
  final int framesAnalyzed;
  final Map<String, double> emotionScores;
  final double valence;
  final double arousal;

  /// Convert to the map format expected by FeatureApi.analyzeMood cameraObservation.
  Map<String, dynamic> toMap() => {
        'dominantEmotion': emotion,
        'emotionScores': emotionScores,
        'faceDetected': true,
        'faceCount': 1,
        'faceQuality': faceQuality,
        'valence': valence,
        'arousal': arousal,
        'framesAnalyzed': framesAnalyzed,
      };
}

/// Camera-based mood check-in: live preview → face detection → emotion
/// classification → temporal smoothing → user confirmation.
class CameraMoodScreen extends StatefulWidget {
  const CameraMoodScreen({super.key});

  @override
  State<CameraMoodScreen> createState() => _CameraMoodScreenState();
}

class _CameraMoodScreenState extends State<CameraMoodScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  final EmotionClassifier _classifier = EmotionClassifier();
  bool _isProcessing = false;
  bool _cameraReady = false;
  String? _error;

  // Frame throttling — process at most 1 frame per _frameInterval
  DateTime _lastProcessedAt = DateTime(0);
  static const Duration _frameInterval = Duration(milliseconds: 400);

  // Temporal smoothing: buffer of recent emotion readings
  final List<_EmotionReading> _readingBuffer = [];
  static const int _maxBufferSize = 10;
  static const int _minStableFrames = 4;

  // Current stable result
  _EmotionReading? _stableResult;
  int _framesAnalyzed = 0;
  bool _modelLoading = true;

  // Animation for processing indicator
  late AnimationController _pulseController;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_cameraReady || _cameraController == null) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Stop frame processing when app goes to background
      _cameraController?.stopImageStream();
      _isProcessing = false;
    } else if (state == AppLifecycleState.resumed) {
      // Resume frame processing
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        _cameraController!.startImageStream(_processFrame);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadModelAndCamera();
  }

  Future<void> _loadModelAndCamera() async {
    await _classifier.loadModel();
    if (mounted) {
      setState(() => _modelLoading = false);
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = 'Camera permission is required for mood check-in.');
      return;
    }

    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.low, // 320x240 — fast for face detection
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // Face detector: classification only (smiling + eye open)
      // No contours/landmarks — too expensive for real-time mobile
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableLandmarks: false,
          enableClassification: true, // smilingProbability, eyeOpenProbability
          enableTracking: false,
          minFaceSize: 0.15,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      // Start frame processing
      _cameraController!.startImageStream(_processFrame);

      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing || _faceDetector == null || _cameraController == null) return;

    // Throttle: skip frames processed too quickly
    final now = DateTime.now();
    if (now.difference(_lastProcessedAt) < _frameInterval) return;
    _lastProcessedAt = now;
    _isProcessing = true;

    try {
      final camera = _cameraController!.description;
      final nv21Bytes = _concatenatePlanes(image.planes);
      final inputImage = InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _rotationIntToImageRotation(
            camera.sensorOrientation,
          ),
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isEmpty || faces.length > 1) {
        if (mounted) {
          setState(() {
            _stableResult = null;
            _readingBuffer.clear();
          });
        }
        _isProcessing = false;
        return;
      }

      final face = faces.first;

      // Convert NV21 → RGB for TFLite classifier
      final rgbBytes = EmotionClassifier.nv21ToRgb(
        nv21Bytes,
        image.width,
        image.height,
      );

      // Classify emotion using TFLite model
      final result = _classifier.classify(
        rgbBytes: rgbBytes,
        frameWidth: image.width,
        frameHeight: image.height,
        face: face,
      );

      final reading = _EmotionReading(
        emotion: result.emotion,
        confidence: result.confidence,
        faceQuality: result.faceQuality,
        scores: result.scores,
        valence: result.valence,
        arousal: result.arousal,
      );

      _framesAnalyzed++;

      // Temporal smoothing
      _readingBuffer.add(reading);
      if (_readingBuffer.length > _maxBufferSize) {
        _readingBuffer.removeAt(0);
      }

      // Check if we have a stable result
      final stable = _getStableResult();
      if (stable != null && mounted) {
        setState(() => _stableResult = stable);
      }
    } catch (_) {
      // Frame processing error — skip silently
    } finally {
      _isProcessing = false;
    }
  }

  /// Check if recent readings are stable (same emotion in last N frames).
  _EmotionReading? _getStableResult() {
    if (_readingBuffer.length < _minStableFrames) return null;

    final recent = _readingBuffer.sublist(
      _readingBuffer.length - _minStableFrames,
    );

    // Count how many frames agree on dominant emotion (skip "unknown")
    final knownReadings =
        recent.where((r) => r.emotion != 'unknown').toList();
    if (knownReadings.length < (_minStableFrames * 0.6).ceil()) {
      // Too many "unknown" readings — not enough data
      return null;
    }

    // Check if all known readings agree on dominant emotion
    final dominant = knownReadings.first.emotion;
    final allAgree = knownReadings.every((r) => r.emotion == dominant);
    if (!allAgree) return null;

    // Average the readings for the stable result
    final avgConfidence =
        recent.map((r) => r.confidence).reduce((a, b) => a + b) /
            recent.length;
    final avgQuality =
        recent.map((r) => r.faceQuality).reduce((a, b) => a + b) /
            recent.length;
    final avgValence =
        recent.map((r) => r.valence).reduce((a, b) => a + b) / recent.length;
    final avgArousal =
        recent.map((r) => r.arousal).reduce((a, b) => a + b) / recent.length;

    // Merge scores by averaging
    final mergedScores = <String, double>{};
    for (final r in recent) {
      r.scores.forEach((k, v) {
        mergedScores[k] = (mergedScores[k] ?? 0.0) + v / recent.length;
      });
    }

    // If average confidence is below threshold, return "unknown"
    final emotion = avgConfidence >= EmotionClassifier.confidenceThreshold
        ? dominant
        : 'unknown';

    return _EmotionReading(
      emotion: emotion,
      confidence: avgConfidence,
      faceQuality: avgQuality,
      scores: mergedScores,
      valence: avgValence,
      arousal: avgArousal,
    );
  }

  void _confirm() {
    if (_stableResult == null) return;
    final r = _stableResult!;
    Navigator.of(context).pop(CameraMoodResult(
      emotion: r.emotion,
      confidence: r.confidence,
      faceQuality: r.faceQuality,
      framesAnalyzed: _framesAnalyzed,
      emotionScores: r.scores,
      valence: r.valence,
      arousal: r.arousal,
    ),);
  }

  void _retry() {
    setState(() {
      _stableResult = null;
      _readingBuffer.clear();
      _framesAnalyzed = 0;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector?.close();
    _classifier.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FeatureScaffold(
      title: 'Camera Mood Check-in',
      body: _error != null
          ? _ErrorView(error: _error!, onRetry: _initCamera)
          : !_cameraReady
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      if (_modelLoading) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Loading emotion model...',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // Camera preview (mirrored for front camera)
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..setEntry(0, 0, -1.0),
                      child: CameraPreview(_cameraController!),
                    ),

                    // Face guide overlay
                    if (_stableResult == null)
                      Center(
                        child: Container(
                          width: 220,
                          height: 280,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.6),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(110),
                          ),
                        ),
                      ),

                    // Status bar at top
                    Positioned(
                      top: AppSpacing.lg,
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      child: _StatusBar(
                        stableResult: _stableResult,
                        framesAnalyzed: _framesAnalyzed,
                        pulseAnimation: _pulseController,
                      ),
                    ),

                    // Bottom controls
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _BottomControls(
                        stableResult: _stableResult,
                        onConfirm: _confirm,
                        onRetry: _retry,
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Helpers ──

Uint8List _concatenatePlanes(List<Plane> planes) {
  final builder = BytesBuilder();
  for (final plane in planes) {
    builder.add(plane.bytes);
  }
  return builder.takeBytes();
}

InputImageRotation _rotationIntToImageRotation(int rotation) {
  switch (rotation) {
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      return InputImageRotation.rotation0deg;
  }
}

// ── Internal types ──

class _EmotionReading {
  const _EmotionReading({
    required this.emotion,
    required this.confidence,
    required this.faceQuality,
    required this.scores,
    required this.valence,
    required this.arousal,
  });

  final String emotion;
  final double confidence;
  final double faceQuality;
  final Map<String, double> scores;
  final double valence;
  final double arousal;
}

// ── Sub-widgets ──

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.stableResult,
    required this.framesAnalyzed,
    required this.pulseAnimation,
  });

  final _EmotionReading? stableResult;
  final int framesAnalyzed;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasResult = stableResult != null;
    final isUnknown = hasResult && stableResult!.emotion == 'unknown';

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: hasResult
                ? isUnknown
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.colorScheme.primaryContainer
                : theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppSpacing.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasResult) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.primary
                          .withValues(alpha: 0.3 + pulseAnimation.value * 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Detecting face... ($framesAnalyzed frames)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ] else if (isUnknown) ...[
                Icon(
                  Icons.help_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Unable to determine emotion',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${stableResult!.emotion[0].toUpperCase()}${stableResult!.emotion.substring(1)} '
                  '· ${(stableResult!.confidence * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.stableResult,
    required this.onConfirm,
    required this.onRetry,
  });

  final _EmotionReading? stableResult;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            theme.colorScheme.surface.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: SafeArea(
        child: stableResult == null
            ? Text(
                'Position your face inside the oval.\n'
                'Hold still for a moment.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : stableResult!.emotion == 'unknown'
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not determine emotion with confidence.\n'
                        'Try better lighting or a clearer face angle.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try Again'),
                        ),
                      ),
                    ],
                  )
                : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      label: 'Use This',
                      icon: Icons.check_rounded,
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
