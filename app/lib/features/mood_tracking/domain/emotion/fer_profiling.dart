/// Production pipeline profiler for the Camera Mood Check-in.
///
/// Measures every stage SEPARATELY so the bottleneck is identified by data,
/// not by guessing:
///
/// - camera init, frame conversion, face detection, face tracking,
///   face crop, preprocessing, model inference, post-processing
///   (softmax/decode + calibration), temporal smoothing, total end-to-end
/// - memory estimate (reused vs allocated buffers)
/// - effective inference FPS, dropped frames
///
/// Usage: one [FerPipelineProfiler] per screen session. Call [begin]/[end]
/// around each stage from the frame path, [dropFrame] for every skipped
/// frame, and [snapshot] (throttled by the caller to <=1-2/sec) to read the
/// aggregated report for logging/UI. Zero allocations on the hot path beyond
/// a fixed-size ring of samples.
///
/// On SM-M325F there is no adb profiler attached in production, so this is
/// the sanctioned way to collect the before/after benchmark table required
/// for the production-readiness sign-off.
library;

import 'dart:math' as math;

/// Stage identifiers. Keep stable — benchmark logs are grepped by name.
enum FerStage {
  cameraInit,
  frameConvert, // packNv21 + upright gray/RGB
  faceDetect, // ML Kit full detection
  faceTrack, // tracker decision (cache hit path)
  faceCrop, // alignment warp / ROI crop
  preprocess, // RGB -> NCHW float tensor
  inference, // interpreter run() only
  postprocess, // softmax decode + calibration + gate decision
  temporal, // EMA fusion + vote
  endToEnd, // classifyFrame wall clock
}

/// One aggregated benchmark report.
class FerProfileReport {
  const FerProfileReport({
    required this.stageAvgMs,
    required this.stageMaxMs,
    required this.framesAnalyzed,
    required this.droppedFrames,
    required this.effectiveFps,
    required this.estimatedLiveBytes,
    required this.backend,
    required this.modelId,
  });

  final Map<String, double> stageAvgMs;
  final Map<String, double> stageMaxMs;
  final int framesAnalyzed;
  final int droppedFrames;
  final double effectiveFps;
  final int estimatedLiveBytes;
  final String backend;
  final String modelId;

  /// Single-line log format: `FER_PROFILE k=v ...` for on-device collection.
  String toLogLine() {
    final sb = StringBuffer('FER_PROFILE');
    stageAvgMs.forEach((k, v) => sb.write(' $k=${v.toStringAsFixed(1)}ms'));
    sb.write(' fps=${effectiveFps.toStringAsFixed(2)}');
    sb.write(' analyzed=$framesAnalyzed dropped=$droppedFrames');
    sb.write(' liveKB=${(estimatedLiveBytes / 1024).toStringAsFixed(0)}');
    sb.write(' backend=$backend model=$modelId');
    return sb.toString();
  }

  Map<String, dynamic> toMap() => {
        'stagesAvgMs': Map<String, double>.from(stageAvgMs),
        'stagesMaxMs': Map<String, double>.from(stageMaxMs),
        'framesAnalyzed': framesAnalyzed,
        'droppedFrames': droppedFrames,
        'effectiveFps': effectiveFps,
        'estimatedLiveBytes': estimatedLiveBytes,
        'backend': backend,
        'modelId': modelId,
      };
}

class _Ring {
  _Ring(this.capacity);
  final int capacity;
  final List<double> _v = [];
  double _sum = 0;
  double max = 0;

  void add(double ms) {
    _v.add(ms);
    _sum += ms;
    if (ms > max) max = ms;
    if (_v.length > capacity) _sum -= _v.removeAt(0);
  }

  double get avg => _v.isEmpty ? 0.0 : _sum / _v.length;
  int get count => _v.length;
}

class FerPipelineProfiler {
  FerPipelineProfiler({this.windowSize = 50});

  final int windowSize;
  final Map<FerStage, _Ring> _rings = {};
  final Map<FerStage, Stopwatch> _open = {};

  int framesAnalyzed = 0;
  int droppedFrames = 0;
  DateTime? _firstFrameAt;
  String backend = 'unknown';
  String modelId = 'unknown';

  /// Bytes the pipeline currently holds across reused buffers. Updated by
  /// the classifier/screen whenever a reusable buffer is (re)allocated so
  /// leaks show up as monotonic growth in the profile line.
  int estimatedLiveBytes = 0;

  _Ring _ring(FerStage s) =>
      _rings.putIfAbsent(s, () => _Ring(windowSize));

  /// Start timing [stage]. Must be paired with [end]. Not re-entrant per
  /// stage (the frame path never nests the same stage).
  void begin(FerStage stage) {
    _open[stage] = Stopwatch()..start();
  }

  /// Stop timing [stage] and record the sample in milliseconds.
  double end(FerStage stage) {
    final sw = _open.remove(stage);
    if (sw == null) return 0.0;
    sw.stop();
    final ms = sw.elapsedMicroseconds / 1000.0;
    _ring(stage).add(ms);
    return ms;
  }

  /// Record a stage sample directly when the caller owns the stopwatch
  /// (e.g. the classifier's internal micro-timings).
  void record(FerStage stage, double ms) => _ring(stage).add(ms);

  void countFrame() {
    framesAnalyzed++;
    _firstFrameAt ??= DateTime.now();
  }

  void dropFrame() => droppedFrames++;

  void reset() {
    _rings.clear();
    _open.clear();
    framesAnalyzed = 0;
    droppedFrames = 0;
    _firstFrameAt = null;
    estimatedLiveBytes = 0;
  }

  double get effectiveFps {
    final t0 = _firstFrameAt;
    if (t0 == null || framesAnalyzed == 0) return 0.0;
    final wallMs = DateTime.now().difference(t0).inMilliseconds;
    if (wallMs <= 0) return 0.0;
    return framesAnalyzed / (wallMs / 1000.0);
  }

  /// Dominant bottleneck: stage with the largest average latency.
  FerStage? get bottleneck {
    FerStage? top;
    var topAvg = 0.0;
    _rings.forEach((stage, ring) {
      if (stage == FerStage.endToEnd) return;
      if (ring.count > 0 && ring.avg > topAvg) {
        topAvg = ring.avg;
        top = stage;
      }
    });
    return top;
  }

  FerProfileReport snapshot() {
    final avg = <String, double>{};
    final max = <String, double>{};
    for (final s in FerStage.values) {
      final r = _rings[s];
      avg[s.name] = r == null ? 0.0 : r.avg;
      max[s.name] = r == null ? 0.0 : r.max;
    }
    // Round to 0.1 ms for log readability.
    avg.updateAll((_, v) => (v * 10).round() / 10);
    max.updateAll((_, v) => math.max(0.0, (v * 10).round() / 10));
    return FerProfileReport(
      stageAvgMs: avg,
      stageMaxMs: max,
      framesAnalyzed: framesAnalyzed,
      droppedFrames: droppedFrames,
      effectiveFps: (effectiveFps * 100).round() / 100,
      estimatedLiveBytes: estimatedLiveBytes,
      backend: backend,
      modelId: modelId,
    );
  }
}
