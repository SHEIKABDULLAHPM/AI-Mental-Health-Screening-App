import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_classifier.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_photo_pipeline.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_preloader.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_result.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Result returned from the camera mood check-in.
///
/// [emotion] is a canonical 7-class emotion id or 'unknown'. [toMap]
/// preserves the legacy cameraObservation keys and adds the versioned
/// keys (status, calibratedConfidence, modelId/Version).
class CameraMoodResult {
  const CameraMoodResult({
    required this.emotion,
    required this.confidence,
    required this.faceQuality,
    required this.framesAnalyzed,
    this.emotionScores = const {},
    this.valence = 0.0,
    this.arousal = 0.0,
    this.status = 'PREDICTED',
    this.calibratedConfidence = 0.0,
    this.modelId = 'vit-fer-7',
    this.modelVersion = 'unknown',
    this.preprocessingVersion = 'unknown',
  });

  final String emotion;
  final double confidence;
  final double faceQuality;
  final int framesAnalyzed;
  final Map<String, double> emotionScores;
  final double valence;
  final double arousal;
  final String status;
  final double calibratedConfidence;
  final String modelId;
  final String modelVersion;
  final String preprocessingVersion;

  factory CameraMoodResult.fromFer(FerResult r, int framesAnalyzed) =>
      CameraMoodResult(
        emotion: r.emotion,
        confidence: r.calibratedConfidence,
        faceQuality: r.faceQuality,
        framesAnalyzed: framesAnalyzed,
        emotionScores: r.scores,
        valence: r.valence,
        arousal: r.arousal,
        status: r.status.wire,
        calibratedConfidence: r.calibratedConfidence,
        modelId: r.modelId,
        modelVersion: r.modelVersion,
        preprocessingVersion: r.preprocessingVersion,
      );

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
        'status': status,
        'calibratedConfidence': calibratedConfidence,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'preprocessingVersion': preprocessingVersion,
      };

  /// Payload for POST /emotions/events (CreateEmotionEventRequest schema).
  /// Distinct from [toMap] (the mood-analyze cameraObservation shape) so each
  /// backend contract gets exactly the keys it validates — never a merged
  /// blob, never double-sent.
  Map<String, dynamic> toEventMap({
    required String capturedAt,
    required String idempotencyKey,
  }) =>
      {
        'emotion': emotion,
        'scores': emotionScores,
        'calibratedConfidence': calibratedConfidence,
        'faceQuality': faceQuality,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'preprocessingVersion': preprocessingVersion,
        'status': status,
        'source': 'CAMERA',
        'capturedAt': capturedAt,
        'idempotencyKey': idempotencyKey,
      };
}

/// User-visible screen phase. Exactly one is active at a time; every phase
/// has a single plain-language label and a clear recovery path.
enum _Phase {
  preparing,
  positioning,
  capturing,
  analyzing,
  detected,
  error,
}

/// Camera-based mood check-in (capture-photo flow).
///
/// Performance design — the fix for the frozen-preview bug:
///
/// - The preview runs with NO image stream, ever. One tap = one
///   `takePicture` (a platform shutter the user already expects to pause the
///   preview for a beat), then analysis only.
/// - JPEG decode runs in the platform image codec (native, async).
/// - Face crop / alignment / photometric quality run in a background isolate
///   via [compute] ([fer_photo_pipeline.dart]).
/// - Only the 224x224 tensor normalization + `Interpreter.run` remain on the
///   calling isolate, on 50K pixels instead of ~1M.
///
/// This screen makes zero network calls and zero database writes: the single
/// user-confirmed [CameraMoodResult] travels out via `Navigator.pop` and is
/// persisted exactly once downstream (one analyze, one mood record, one
/// emotion event — see RecordMoodScreen).
class CameraMoodScreen extends StatefulWidget {
  const CameraMoodScreen({super.key});

  @override
  State<CameraMoodScreen> createState() => _CameraMoodScreenState();
}

class _CameraMoodScreenState extends State<CameraMoodScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  FerClassifier _classifier = FerClassifier();

  _Phase _phase = _Phase.preparing;
  bool _modelReady = false;

  /// Fatal (retry-or-skip) error text. Null while positioning/capturing.
  String? _error;

  /// Whether the OS permission request ended in "permanently denied", in
  /// which case retrying is pointless and we offer system settings instead.
  bool _permissionPermanentlyDenied = false;

  /// Confirmed-quality single-photo result awaiting the user's decision.
  FerResult? _photoResult;

  /// Plain-language guidance for the last unusable capture (null = none).
  String? _guidance;

  // Single-flight guards: late permission grants and retries must not build
  // a second controller while one already exists; double-taps must not start
  // a second analysis.
  bool _initStarted = false;
  bool _busy = false;
  bool _disposed = false;

  late AnimationController _pulseController;

  bool get _cameraReady =>
      _cameraController != null &&
      _cameraController!.value.isInitialized;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _startPipeline();
  }

  /// Bring the screen up fast: camera preview and model load run
  /// concurrently. The preview (platform texture) renders as soon as the
  /// camera initializes while the model loads in the background; capture
  /// simply waits for [_modelReady]. Neither future is awaited here so slow
  /// model I/O can never block camera startup.
  void _startPipeline() {
    if (_initStarted) return;
    _initStarted = true;
    _initCamera();
    _loadModel();
  }

  Future<void> _loadModel() async {
    if (_disposed) return;
    // Adopt a pre-warmed interpreter when one is waiting (warmed while the
    // user answered the surrounding questions). Ownership transfers: the
    // holder forgets it and this screen disposes it exactly as before.
    final warm = FerPreloader.take();
    if (warm != null) {
      _classifier.dispose();
      _classifier = warm;
      if (mounted) {
        setState(() {
          _modelReady = true;
          if (_phase == _Phase.preparing && _cameraReady) {
            _phase = _Phase.positioning;
          }
        });
      }
      return;
    }
    if (_classifier.isReady) {
      if (mounted && !_modelReady) {
        setState(() {
          _modelReady = true;
          if (_phase == _Phase.preparing && _cameraReady) {
            _phase = _Phase.positioning;
          }
        });
      }
      return;
    }
    try {
      await _classifier.load(
        manifestAsset: 'assets/models/vit_fer_manifest.json',
      );
    } catch (e) {
      debugPrint('FER model load failed: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = 'Camera reading isn\'t available. '
              'You can continue without it.';
        });
      }
      return;
    }
    if (_disposed || !mounted) return;
    setState(() {
      _modelReady = true;
      if (_phase == _Phase.preparing && _cameraReady) {
        _phase = _Phase.positioning;
      }
    });
  }

  /// Retry after a fatal error. The loaded model is reused when available —
  /// a reload is never forced by a camera failure.
  Future<void> _retryPipeline() async {
    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
      } catch (_) {}
      _cameraController = null;
    }
    try {
      await _faceDetector?.close();
    } catch (_) {}
    _faceDetector = null;
    _initStarted = false;
    if (mounted) {
      setState(() {
        _phase = _Phase.preparing;
        _error = null;
        _permissionPermanentlyDenied = false;
        _photoResult = null;
        _guidance = null;
      });
    }
    _startPipeline();
  }

  Future<void> _initCamera() async {
    if (_disposed) return;
    if (_cameraController != null) return;
    final status = await Permission.camera.request();
    if (_disposed || !mounted) return;
    if (!status.isGranted) {
      setState(() {
        _phase = _Phase.error;
        _permissionPermanentlyDenied = status.isPermanentlyDenied;
        _error = status.isPermanentlyDenied
            ? 'Camera access is turned off. '
                'You can enable it in settings or continue without it.'
            : 'Camera access isn\'t available. '
                'You can continue without it.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('no cameras');
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Low preset: the smoothest preview with the least CPU/thermal load,
      // and still ample detail — the model only ever sees a 224x224 face
      // crop. No image stream is ever started on this controller.
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableLandmarks: true,
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.10,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      if (_disposed) return;
      if (mounted) {
        setState(() {
          if (_phase == _Phase.preparing && _modelReady) {
            _phase = _Phase.positioning;
          } else if (_phase == _Phase.preparing && !_modelReady) {
            // Camera is live; still waiting on the model in the background.
            // Stay in preparing (shows "Preparing camera...") until both
            // are ready — the shutter stays disabled meanwhile.
          }
        });
      }
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = 'Camera reading isn\'t available. '
              'You can continue without it.';
        });
      }
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  /// One tap = one photo = one analysis. Guarded against double-taps; the
  /// preview is stream-free so it never stutters while analysis runs.
  Future<void> _capture() async {
    final controller = _cameraController;
    if (_busy ||
        _phase != _Phase.positioning ||
        controller == null ||
        !_cameraReady ||
        !_modelReady) {
      return;
    }
    setState(() {
      _busy = true;
      _phase = _Phase.capturing;
      _guidance = null;
    });
    XFile? photo;
    try {
      photo = await controller
          .takePicture()
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.positioning;
        _guidance = 'The camera took too long. Please try again.';
      });
      return;
    } catch (e) {
      debugPrint('Capture failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.positioning;
        _guidance = "We couldn't take the photo. Please try again.";
      });
      return;
    }

    if (_disposed || !mounted) {
      await _deleteQuietly(photo.path);
      return;
    }
    setState(() => _phase = _Phase.analyzing);
    // Let the "Analyzing..." state paint before the inference below.
    await Future<void>.delayed(Duration.zero);

    try {
      final result = await _analyzePhoto(photo.path)
          .timeout(const Duration(seconds: 25));
      await _deleteQuietly(photo.path);
      if (_disposed || !mounted) return;
      setState(() {
        _busy = false;
        if (result != null && result.status == FerStatus.predicted) {
          _phase = _Phase.detected;
          _photoResult = result;
        } else {
          _phase = _Phase.positioning;
          _guidance = _messageFor(result?.status);
        }
      });
    } on TimeoutException {
      await _deleteQuietly(photo.path);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.positioning;
        _guidance = 'Analysis took too long. Please try again.';
      });
    } catch (e) {
      debugPrint('Photo analysis failed: $e');
      await _deleteQuietly(photo.path);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.positioning;
        _guidance = "We couldn't get a clear reading. Please try again.";
      });
    }
  }

  /// Capture-photo analysis: ML Kit (native, async) -> codec decode (native,
  /// async) -> face preparation (background isolate) -> single local
  /// inference. Returns null only on infrastructure failure; quality outcomes
  /// arrive as [FerResult] with the corresponding status. Never invents an
  /// emotion, never touches the network.
  Future<FerResult?> _analyzePhoto(String photoPath) async {
    final detector = _faceDetector;
    final FerManifest? manifest = _classifier.manifest;
    if (detector == null || manifest == null || !_classifier.isReady) {
      return null;
    }
    final faces = await detector
        .processImage(InputImage.fromFilePath(photoPath))
        .timeout(const Duration(seconds: 8));
    if (_disposed) return null;

    if (faces.isEmpty) {
      return _statusOnly(manifest, FerStatus.noFace);
    }
    if (faces.length > 1) {
      return _statusOnly(manifest, FerStatus.multipleFaces);
    }

    final face = faces.first;
    final box = face.boundingBox;

    // Geometry + pose gates need no pixels — decide on the UI thread
    // without any allocation.
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (yaw > manifest.maxYawDeg || pitch > manifest.maxPitchDeg) {
      return _statusOnly(manifest, FerStatus.badPose);
    }

    // Decode in the platform codec (native, async — never UI pixel loops).
    // takePicture writes upright pixels, and ML Kit reads the same file, so
    // the detected box maps 1:1 onto the decoded image — no rotation math.
    final jpeg = await File(photoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(jpeg);
    final frame = await codec.getNextFrame();
    final decoded = frame.image;
    ByteData? rgba;
    try {
      rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      decoded.dispose();
      codec.dispose();
    }
    if (rgba == null || _disposed) return null;
    final int imgW = frame.image.width;
    final int imgH = frame.image.height;

    final areaRatio = (box.width * box.height) / (imgW * imgH);
    if (areaRatio < manifest.minFaceSizeRatio) {
      return _statusOnly(manifest, FerStatus.faceTooSmall);
    }

    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;    if (leftEye == null && rightEye == null) {
      return _statusOnly(manifest, FerStatus.faceOccluded);
    }

    // Heavy pixel work (crop/warp/resize/quality) in a background isolate.
    final prep = await prepareFaceOffThread(
      PhotoPrepArgs(
        rgba: rgba.buffer.asUint8List(),
        srcWidth: imgW,
        srcHeight: imgH,
        faceLeft: box.left.toDouble(),
        faceTop: box.top.toDouble(),
        faceRight: box.right.toDouble(),
        faceBottom: box.bottom.toDouble(),
        leftEyeX: leftEye?.x.toDouble(),
        leftEyeY: leftEye?.y.toDouble(),
        rightEyeX: rightEye?.x.toDouble(),
        rightEyeY: rightEye?.y.toDouble(),
        outputSize: manifest.inputWidth,
      ),
    ).timeout(const Duration(seconds: 10));
    if (_disposed) return null;

    // Photometric gates on the isolate-measured scalars (same semantics and
    // thresholds as the streaming path — one shared manifest).
    if (prep.brightness < manifest.minBrightness ||
        prep.brightness > manifest.maxBrightness ||
        prep.contrast < manifest.minContrast) {
      return _statusOnly(manifest, FerStatus.badLighting);
    }
    if (prep.sharpness < manifest.minSharpness) {
      return _statusOnly(manifest, FerStatus.faceTooBlurry);
    }

    final quality = _combineQuality(
      areaRatio: areaRatio,
      yawDeg: yaw,
      pitchDeg: pitch,
      brightness: prep.brightness,
      contrast: prep.contrast,
      sharpness: prep.sharpness,
      manifest: manifest,
    );

    // The only work left on this isolate: normalize 50K pixels (a few ms)
    // plus one 224x224 interpreter run. Everything full-frame already
    // happened natively or in the background isolate.
    try {
      return _classifier.classifyPreparedFace(
        alignedRgb: prep.alignedRgb,
        alignMethod: prep.alignMethod,
        eyeDistance: prep.eyeDistance,
        quality: quality,
        qualityDetails: {
          'faceSizeRatio': areaRatio,
          'yawDeg': yaw,
          'pitchDeg': pitch,
          'brightness': prep.brightness,
          'contrast': prep.contrast,
          'sharpness': prep.sharpness,
          'eyeDistance': prep.eyeDistance,
        },
      );
    } on FerException catch (e) {
      debugPrint('FER photo inference failed (${e.code}): ${e.message}');
      return null;
    }
  }

  /// Cheap scalar quality blend for reporting only — gating already happened
  /// above, so this never invents or suppresses a result.
  double _combineQuality({
    required double areaRatio,
    required double yawDeg,
    required double pitchDeg,
    required double brightness,
    required double contrast,
    required double sharpness,
    required FerManifest manifest,
  }) {
    final sizeScore = (areaRatio / 0.15).clamp(0.3, 1.0);
    final poseScore =
        (1.0 - (yawDeg / (manifest.maxYawDeg * 2))).clamp(0.5, 1.0) *
            (1.0 - (pitchDeg / (manifest.maxPitchDeg * 2))).clamp(0.5, 1.0);
    final lightScore =
        (contrast / (manifest.minContrast * 3)).clamp(0.5, 1.0);
    final sharpScore =
        (sharpness / (manifest.minSharpness * 3)).clamp(0.5, 1.0);
    // Brightness near the mid-range scores best; extremes that passed the
    // gate still report slightly lower quality.
    final brightScore =
        (1.0 - ((brightness - 128.0).abs() / 256.0)).clamp(0.5, 1.0);
    return (sizeScore * 0.30 +
            poseScore * 0.25 +
            lightScore * 0.15 +
            sharpScore * 0.15 +
            brightScore * 0.15)
        .clamp(0.0, 1.0);
  }

  FerResult _statusOnly(FerManifest m, FerStatus s) => FerResult(
        emotion: 'unknown',
        scores: {for (final c in m.classes) c: 0.0},
        calibratedConfidence: 0.0,
        rawTopProbability: 0.0,
        margin: 0.0,
        faceQuality: 0.0,
        status: s,
        modelId: m.modelId,
        modelVersion: m.version,
        preprocessingVersion: m.preprocessingVersion,
        valence: 0.0,
        arousal: 0.0,
        framesAnalyzed: 1,
        delegate: _classifier.delegate,
      );

  /// Plain-language guidance per capture outcome. Internal thresholds stay
  /// internal — the user gets one actionable sentence.
  static String _messageFor(FerStatus? s) => switch (s) {
        FerStatus.noFace => 'Position your face inside the frame.',
        FerStatus.multipleFaces => 'Make sure only one face is visible.',
        FerStatus.faceTooSmall => 'Move a little closer.',
        FerStatus.faceTooBlurry => 'Hold still and capture again.',
        FerStatus.faceOccluded => 'Keep your face fully visible.',
        FerStatus.badLighting => 'Try moving to a brighter place.',
        FerStatus.badPose => 'Face the camera directly.',
        _ => "We couldn't get a clear reading. Please try again.",
      };

  static Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  void _confirm() {
    final r = _photoResult;
    if (r == null || r.status != FerStatus.predicted) return;
    Navigator.of(context).pop(CameraMoodResult.fromFer(r, 1));
  }

  /// Leave without a camera result. Null means "continue with the
  /// self-reported mood" to every caller — never an error.
  void _skip() {
    if (mounted) Navigator.of(context).pop();
  }

  /// Discard the last result/message and return to positioning.
  void _retake() {
    if (_busy) return;
    setState(() {
      _phase = _Phase.positioning;
      _photoResult = null;
      _guidance = null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_cameraController?.dispose());
    unawaited(_faceDetector?.close().catchError((_) {}));
    _classifier.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_phase == _Phase.error) {
      return FeatureScaffold(
        title: 'Camera Mood Check-in',
        body: _ErrorView(
          error: _error ?? 'Camera reading isn\'t available.',
          showSettings: _permissionPermanentlyDenied,
          onOpenSettings: _openSettings,
          onRetry: _retryPipeline,
          onSkip: _skip,
        ),
      );
    }

    if (!_cameraReady || _phase == _Phase.preparing) {
      return FeatureScaffold(
        title: 'Camera Mood Check-in',
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Preparing camera...',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final hasResult = _phase == _Phase.detected && _photoResult != null;
    final busy = _busy;
    final emotionLabel =
        hasResult ? ferDisplayName(_photoResult!.emotion) : null;

    return FeatureScaffold(
      title: 'Camera Mood Check-in',
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Stream-free preview (mirrored for the front camera). Analysis
          // only ever runs on a captured photo, so preview smoothness never
          // depends on inference.
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..setEntry(0, 0, -1.0),
            child: CameraPreview(_cameraController!),
          ),

          // Face guide overlay
          if (!hasResult)
            Center(
              child: Container(
                width: 220,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        theme.colorScheme.primary.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(110),
                ),
              ),
            ),

          // Status bar at top: one plain-language state, never internals.
          Positioned(
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: _StatusBar(
              stateLabel: !_modelReady
                  ? 'Preparing camera...'
                  : switch (_phase) {
                      _Phase.capturing => 'Capturing...',
                      _Phase.analyzing => 'Analyzing...',
                      _Phase.detected => 'Mood detected',
                      _Phase.positioning => _guidance ??
                          'Position your face inside the frame.',
                      _Phase.preparing || _Phase.error =>
                        'Preparing camera...',
                    },
              confirmed: hasResult,
              emotionLabel: emotionLabel,
              pulseAnimation: _pulseController,
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomControls(
              hasResult: hasResult,
              busy: busy,
              canCapture: _modelReady && !busy && !hasResult,
              onCapture: _capture,
              onConfirm: _confirm,
              onRetake: _retake,
              onSkip: _skip,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top status pill. Shows one plain-language state — never confidence
/// percentages, margins, frame counts, or model internals.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.stateLabel,
    required this.confirmed,
    required this.emotionLabel,
    required this.pulseAnimation,
  });

  final String stateLabel;
  final bool confirmed;
  final String? emotionLabel;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = confirmed
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface.withValues(alpha: 0.85);

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSpacing.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!confirmed) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.primary.withValues(
                        alpha: 0.3 + pulseAnimation.value * 0.7,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    stateLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    // Neutral language: captured expression, never a
                    // mental-health interpretation.
                    'Mood detected${emotionLabel != null ? ': $emotionLabel' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
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
    required this.hasResult,
    required this.busy,
    required this.canCapture,
    required this.onCapture,
    required this.onConfirm,
    required this.onRetake,
    required this.onSkip,
  });

  final bool hasResult;
  final bool busy;
  final bool canCapture;
  final VoidCallback onCapture;
  final VoidCallback onConfirm;
  final VoidCallback onRetake;
  final VoidCallback onSkip;

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
        child: hasResult
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Does this feel right?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : onRetake,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retake'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppButton(
                          label: 'Continue',
                          icon: Icons.check_rounded,
                          onPressed: busy ? null : onConfirm,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Shutter: disabled while the model still loads or a
                  // capture/analysis is in flight — double-taps and
                  // double-submissions are structurally impossible.
                  Center(
                    child: _CaptureButton(
                      busy: busy,
                      enabled: canCapture,
                      onTap: onCapture,
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : onSkip,
                    child: const Text('Skip for now'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Round shutter button. One tap = one photo = one analysis.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton.filled(
      tooltip: 'Capture',
      iconSize: 32,
      padding: const EdgeInsets.all(AppSpacing.md),
      onPressed: !enabled ? null : onTap,
      icon: busy
          ? const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : const Icon(Icons.camera_alt_rounded),
      style: IconButton.styleFrom(
        backgroundColor: enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.showSettings,
    required this.onOpenSettings,
    required this.onRetry,
    required this.onSkip,
  });

  final String error;
  final bool showSettings;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

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
            if (showSettings)
              AppButton(
                label: 'Open settings',
                icon: Icons.settings_rounded,
                onPressed: onOpenSettings,
              ),
            AppButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
            TextButton(
              onPressed: onSkip,
              child: const Text('Continue without camera'),
            ),
          ],
        ),
      ),
    );
  }
}
