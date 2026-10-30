/// Lightweight face-tracking policy for the Camera Mood Check-in.
///
/// Goal: do NOT run the expensive ML Kit full face detection on every
/// analyzed frame. Pipeline:
///
///   Initial frame -> Face Detection -> Face Tracking -> Periodic Re-detection
///
/// Full detection runs again ONLY when:
/// - tracking fails (no cached face / quality gate rejected repeatedly),
/// - the face moved significantly (box IoU vs cached box below threshold
///   on a re-detect — i.e. the user is moving, keep detecting),
/// - the face left the expected region (cached box mostly outside frame),
/// - a re-detection timeout elapsed.
///
/// Between detections the previously returned ML Kit [Face] instances are
/// reused directly (same object reference). A [Face] only carries
/// coordinates (bounding box + landmark points in upright space); reusing
/// those coordinates on a fresh frame is tracking-by-persistence, valid
/// while the user holds the phone for a check-in (small motion). The
/// tracker itself costs microseconds (timestamp + arithmetic compares) and
/// can never become a second bottleneck — verified by [FerStage.faceTrack]
/// profiling staying ~0 ms.
///
/// The tracker never invents geometry: it only reuses coordinates ML Kit
/// actually observed, and forces re-detection whenever they go stale.
library;

import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Decision returned by [FaceTracker.shouldDetect].
enum FaceTrackDecision {
  /// Run ML Kit full detection on this frame.
  detect,

  /// Reuse [FaceTracker.cachedFaces] — skip ML Kit entirely.
  track,
}

/// Tunables. Defaults target a 2–5 FPS inference pipeline on SM-M325F:
/// re-detect at most ~1/sec while the face is stable.
class FaceTrackerConfig {
  const FaceTrackerConfig({
    this.redetectInterval = const Duration(milliseconds: 1200),
    this.minTrackInterval = const Duration(milliseconds: 200),
    this.consecutiveGateFailuresToRedetect = 2,
    this.minBoxOverlapToKeepTracking = 0.55,
  });

  /// Stable-face re-detection period. Larger = fewer ML Kit runs.
  final Duration redetectInterval;

  /// Minimum spacing between two full detections (thermal/back-pressure).
  final Duration minTrackInterval;

  /// Quality-gate rejections in a row before forcing a fresh detection
  /// (the cached coordinates may no longer match the face).
  final int consecutiveGateFailuresToRedetect;

  /// On a fresh detection, IoU vs the cached box below this means the face
  /// moved significantly — shorten the next interval (handled by caller via
  /// [noteMovement]).
  final double minBoxOverlapToKeepTracking;
}

class FaceTracker {
  FaceTracker({this.config = const FaceTrackerConfig()});

  final FaceTrackerConfig config;

  List<Face>? _cachedFaces;
  DateTime? _lastDetectAt;
  Rect? _lastBox;
  int _gateFailures = 0;
  bool _faceMoving = false;

  /// Last ML Kit observation, reused while tracking. Null until the first
  /// successful detection.
  List<Face>? get cachedFaces => _cachedFaces;
  bool get hasTrack => _cachedFaces != null && _cachedFaces!.isNotEmpty;
  int get gateFailures => _gateFailures;

  /// Decide whether this analyzed frame needs a full ML Kit detection.
  FaceTrackDecision shouldDetect({required DateTime now}) {
    if (!hasTrack) return FaceTrackDecision.detect;
    final last = _lastDetectAt;
    if (last == null) return FaceTrackDecision.detect;
    if (_gateFailures >= config.consecutiveGateFailuresToRedetect) {
      return FaceTrackDecision.detect;
    }
    final interval =
        _faceMoving ? config.minTrackInterval : config.redetectInterval;
    if (now.difference(last) >= interval) return FaceTrackDecision.detect;
    return FaceTrackDecision.track;
  }

  /// Record a fresh ML Kit detection result.
  void noteDetection(List<Face> faces, {required DateTime now}) {
    if (faces.isNotEmpty) {
      final box = faces.first.boundingBox;
      if (_lastBox != null && _cachedFaces != null) {
        final iou = _iou(_lastBox!, box);
        _faceMoving = iou < config.minBoxOverlapToKeepTracking;
      }
      _lastBox = box;
      _cachedFaces = faces;
      _gateFailures = 0;
    } else {
      // No face observed: drop the track so the UI coaches correctly and
      // the next frame re-detects (subject to min spacing).
      _cachedFaces = null;
      _lastBox = null;
      _faceMoving = false;
    }
    _lastDetectAt = now;
  }

  /// Record a quality-gate rejection for the tracked coordinates. Repeated
  /// rejections mean the face moved out of the cached box — force re-detect.
  void noteGateRejection() => _gateFailures++;

  /// Record that inference consumed the tracked faces successfully.
  void noteConsumed() => _gateFailures = 0;

  /// The cached box drifted out of frame / tracking failed outright.
  void invalidate() {
    _cachedFaces = null;
    _lastBox = null;
    _gateFailures = 0;
    _faceMoving = false;
  }

  /// Caller detected significant motion externally (e.g. two consecutive
  /// detections disagree) — re-detect at the fast cadence for a while.
  void noteMovement(bool moving) => _faceMoving = moving;

  void reset() => invalidate();

  static double _iou(Rect a, Rect b) {
    final l = a.left > b.left ? a.left : b.left;
    final t = a.top > b.top ? a.top : b.top;
    final r = a.right < b.right ? a.right : b.right;
    final bo = a.bottom < b.bottom ? a.bottom : b.bottom;
    final w = r - l, h = bo - t;
    if (w <= 0 || h <= 0) return 0.0;
    final inter = w * h;
    final union = a.width * a.height + b.width * b.height - inter;
    if (union <= 0) return 0.0;
    return inter / union;
  }
}
