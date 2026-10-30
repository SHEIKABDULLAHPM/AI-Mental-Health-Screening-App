import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_alignment.dart';
import 'face_quality.dart';
import 'fer_backend.dart';
import 'fer_calibration.dart';
import 'fer_manifest.dart';
import 'fer_preprocessing.dart';
import 'fer_profiling.dart';
import 'fer_result.dart';
import 'fer_temporal.dart';

/// Digest of the model artifact, computed off the UI isolate. Hashing the
/// 172 MB file inline blocked the camera screen for 8.4 s on a real SM-M325F,
/// so this must stay a top-level function for [compute].
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// Numerically stable softmax over raw model logits.
///
/// The shipped ViT artifact emits LOGITS (unbounded, negative allowed, do not
/// sum to 1) — not probabilities. Everything downstream (temperature scaling,
/// confidence/margin gates, temporal EMA, valence, backend payloads) assumes a
/// 7-way distribution, so decoding without this step makes every frame look
/// over-confident and traps the vote on the highest-bias class.
List<double> softmaxLogits(List<double> logits) {
  var maxLogit = logits[0];
  for (var i = 1; i < logits.length; i++) {
    if (logits[i] > maxLogit) maxLogit = logits[i];
  }
  final exps = List<double>.filled(logits.length, 0.0);
  var sum = 0.0;
  for (var i = 0; i < logits.length; i++) {
    final e = math.exp(logits[i] - maxLogit);
    exps[i] = e;
    sum += e;
  }
  for (var i = 0; i < exps.length; i++) {
    exps[i] = exps[i] / sum;
  }
  return exps;
}

/// Decode one output row into a 7-way probability distribution.
///
/// Mirrors the server decoder: values that already form a distribution
/// (non-negative, sum ≈ 1) pass through untouched; raw logits get a softmax.
/// Deciding by values instead of artifact identity keeps this correct if a
/// future model ships with the softmax fused back in.
List<double> decodeOutput(List<double> row) {
  var sum = 0.0;
  var minVal = double.infinity;
  for (final v in row) {
    sum += v;
    if (v < minVal) minVal = v;
  }
  if (minVal >= 0.0 && (sum - 1.0).abs() <= 1e-3) return List<double>.from(row);
  return softmaxLogits(row);
}

/// TEMPORARY diagnostic logging (FER_DIAG).
///
/// Records gate verdicts only — labels, confidence and quality scalars. It
/// never emits pixels, crops or base64: face imagery stays on device and out
/// of logcat, where any app with READ_LOGS (or an adb session) could read it.
/// Structured failure logging (FER_DIAG) is off in production builds.
/// Enable temporarily only for on-device diagnosis; it records gate verdicts
/// and distributions — never pixels, crops or base64.
const bool kFerDiagnostics = false;

/// Structured failure. Inference errors are surfaced to the caller with a
/// code + message and counted in [metrics]; they NEVER synthesize an
/// emotion. Callers map failures to PROCESSING/UNCERTAIN UI states.
class FerException implements Exception {
  FerException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'FerException($code): $message';
}

/// On-device seven-class emotion inference engine (ViT-B/16, fp16).
///
/// Pipeline: manifest -> checksum -> delegate select -> quality gate ->
/// alignment -> preprocessing contract -> model -> calibration ->
/// temporal fusion -> structured result.
class FerClassifier {
  FerClassifier();

  FerManifest? _manifest;
  Interpreter? _interpreter;
  bool _quantized = false;
  String _delegate = 'cpu';

  /// Why [_delegate] was selected (gpu failure reason / fallback chain).
  /// Logged once per load; surfaced in benchmark lines.
  String _delegateReason = 'unloaded';
  Delegate? _gpuDelegate;

  /// Model bytes must outlive the interpreter (memory-mapped). Kept here so
  /// the buffer is never GC'd while inference runs.
  // ignore: unused_field — held for lifetime, not reads.
  ByteData? _modelBlob;
  late FaceQualityGate _gate;
  late RgbFaceAligner _aligner;
  late FerPreprocessing _pre;
  late FerCalibration _cal;
  late FerTemporalFusion _fusion;

  /// Optional per-stage profiler. Null in unit tests / when the screen does
  /// not attach one — zero overhead then.
  FerPipelineProfiler? profiler;

  /// Reusable NCHW input tensor (224*224*3 floats ≈ 600 KB). Allocated once
  /// per load and refilled per frame — never reallocated on the hot path.
  Float32List? _tensorBuf;

  // Observability counters (no images, no personal data).
  int inferenceTotal = 0;
  int inferenceFailureTotal = 0;

  /// Wall-clock duration of the last TFLite run(), in microseconds.
  int _inferenceMicros = 0;

  /// Duration of the last TFLite run() in milliseconds.
  int get lastInferenceMs => (_inferenceMicros / 1000).round();
  int unknownTotal = 0;
  int lowQualityTotal = 0;
  final List<int> latencyMsSamples = [];

  bool get isReady => _manifest != null && _interpreter != null;
  FerManifest? get manifest => _manifest;
  String get delegate => _delegate;
  String get delegateReason => _delegateReason;

  /// Dart-side reusable bytes held across frames (for memory profiling).
  int get liveBytes => _estimateLiveBytes();

  /// Load manifest, verify checksum, create the interpreter.
  ///
  /// [manifestAsset] e.g. 'assets/models/vit_fer_manifest.json'.
  /// The model file is resolved from manifest.productionArtifact under
  /// 'assets/models/'. Throws [FerException] / [FerManifestError] /
  /// [FerContractError] — never half-initializes.
  Future<void> load({required String manifestAsset}) async {
    dispose();
    _fusionReset();
    final swLoad = Stopwatch()..start();
    final raw = await rootBundle.loadString(manifestAsset);
    final manifest = FerManifest.parse(jsonDecode(raw) as Map<String, dynamic>);

    final modelAsset = 'assets/models/${manifest.productionArtifact}';
    final blob = await rootBundle.load(modelAsset);
    final msRead = swLoad.elapsedMilliseconds;
    final modelBytes = blob.buffer.asUint8List();
    final digest = await compute(_sha256Hex, modelBytes);
    final msHash = swLoad.elapsedMilliseconds;
    if (digest != manifest.checksum) {
      throw FerException('MODEL_CHECKSUM_MISMATCH',
          'expected ${manifest.checksum}, got $digest — refusing to load',);
    }

    // Backend selection: GPU -> NNAPI -> CPU/XNNPACK, each attempted
    // independently via [FerBackendProbe]. A GPU delegate that fails (Mali on
    // SM-M325F) is created at most once per process, logged once, and never
    // retried — the failure mode is recorded in [delegateReason], not hidden.
    // The warm-up inside the probe proves the selected backend can EXECUTE
    // this graph, so a delegate that creates cleanly but fails at run time
    // triggers the controlled fallback here — never mid-session.
    _modelBlob = blob; // keep alive: the interpreter memory-maps this buffer
    FerBackendOffer offer;
    try {
      offer = await FerBackendProbe.create(
        modelBytes: modelBytes,
        outputClasses: manifest.classes.length,
        quantized: false, // resolved from the live tensor below; the warm-up
        // closure below re-reads the tensor type itself.
        cpuThreads: 4,
        warmUp: (itp, _) async => _runWarmUp(
            itp, manifest, _isQuantizedTensor(itp.getInputTensor(0)),),
      );
    } on FerException {
      rethrow;
    } catch (e) {
      throw FerException('INTERPRETER_CREATE_FAILED', e.toString());
    }
    final Interpreter itp = offer.interpreter;
    _delegate = offer.label;
    _delegateReason = offer.reason;
    _gpuDelegate = offer.gpuDelegate;
    // Resolve quantization from the LIVE tensor (not the manifest flag): the
    // shipped fp16 artifact reports float32 input even though weights are
    // half precision.

    final msInterp = swLoad.elapsedMilliseconds;

    // Contract validation: THE regression guard for the legacy 48/64 bug.
    final inTensor = itp.getInputTensor(0);
    final shape = inTensor.shape;
    final typeName = inTensor.type.toString().toLowerCase();
    _quantized = typeName.contains('uint8') || typeName.contains('int8');
    FerPreprocessing(manifest)
        .validateTensor(shape: shape, dtype: typeName, quantized: _quantized);

    final outTensor = itp.getOutputTensor(0);
    if (outTensor.shape.length != 2 ||
        outTensor.shape[0] != 1 ||
        outTensor.shape[1] != manifest.classes.length) {
      await _abandonOffer(offer);
      _modelBlob = null;
      throw FerException('MODEL_OUTPUT_MISMATCH',
          'output ${outTensor.shape} != [1,${manifest.classes.length}]',);
    }

    _manifest = manifest;
    _interpreter = itp;
    _gate = FaceQualityGate(manifest);
    _aligner = RgbFaceAligner(outputSize: manifest.inputWidth);
    _pre = FerPreprocessing(manifest);
    _cal = FerCalibration(manifest);
    _fusion = FerTemporalFusion(manifest);
    _tensorBuf = Float32List(
        manifest.inputWidth * manifest.inputHeight * manifest.channels,);

    // The probe already warmed up the selected backend (execution proof), so
    // no second warm-up run here. Attempt latencies are the benchmark
    // evidence for the backend choice — never assume GPU is faster.
    // Timing is diagnostic only; model I/O runs off the camera critical path
    // (the screen loads concurrently with preview startup).
    debugPrint('FER_PERF load read=${msRead}ms sha256=${msHash - msRead}ms '
        'interp=${msInterp - msHash}ms warmup=${swLoad.elapsedMilliseconds - msInterp}ms '
        'delegate=$_delegate reason=$_delegateReason '
        'attempts=${offer.attemptLatenciesMs} '
        'total=${swLoad.elapsedMilliseconds}ms');
    profiler?.estimatedLiveBytes = _estimateLiveBytes();
  }

  /// Release an interpreter offer that failed post-creation validation.
  Future<void> _abandonOffer(FerBackendOffer offer) async {
    await _close(offer.interpreter);
    try {
      offer.gpuDelegate?.delete();
    } catch (_) {}
    if (identical(offer.gpuDelegate, _gpuDelegate)) _gpuDelegate = null;
    _delegate = 'cpu';
    _delegateReason = 'abandoned:${offer.reason}';
  }

  /// True when a live input tensor expects quantized bytes.
  static bool _isQuantizedTensor(Tensor tensor) {
    final t = tensor.type.toString().toLowerCase();
    return t.contains('uint8') || t.contains('int8');
  }

  /// Execution proof for a candidate backend: runs zeros through [itp].
  /// Output length is read from the LIVE tensor (not the manifest) so this
  /// is safe before contract validation. Throws [FerException] when the
  /// backend cannot execute the graph — the probe then falls back.
  static void _runWarmUp(
      Interpreter itp, FerManifest manifest, bool quantized,) {
    final n = manifest.inputWidth * manifest.inputHeight * manifest.channels;
    // Zeros are a legal input for this model, so the run proves the delegate
    // can execute the graph. Buffers are used for the same reason as the real
    // inference path: a flat Float32List would infer a 1-D shape and make the
    // interpreter try to resize a fixed-shape tensor.
    final input = Float32List(n);
    var outLen = manifest.classes.length;
    try {
      final shape = itp.getOutputTensor(0).shape;
      if (shape.length == 2 && shape[1] > 0) outLen = shape[1];
    } catch (_) {}
    if (quantized) {
      final outInts = List.generate(1, (_) => List<int>.filled(outLen, 0));
      itp.run(Uint8List.view(input.buffer), outInts);
      return;
    }
    final outBuf = Float32List(outLen);
    itp.run(input.buffer.asUint8List(), outBuf.buffer);
    for (final v in outBuf) {
      if (!v.isFinite) {
        throw FerException('WARMUP_FAILED', 'warm-up produced non-finite output');
      }
    }
  }

  void _fusionReset() {
    // Fusion is (re)created on load; reset stream state between sessions.
    _fusion = FerTemporalFusion(
        _manifest ?? FerManifest.parse(_fallbackManifestForFusion()),);
  }

  // Minimal valid manifest used only to construct a fusion instance before
  // the real manifest loads; replaced in load(). Never used for inference.
  Map<String, dynamic> _fallbackManifestForFusion() => {
        'modelId': 'vit-fer-7',
        'version': '0.0.0',
        'architecture': 'none',
        'inputWidth': 224,
        'inputHeight': 224,
        'channels': 3,
        'colorSpace': 'RGB',
        'normalization': 'MEAN_STD_0.5',
        'tensorLayout': 'NCHW',
        'classes': List<String>.from(kFerClasses),
        'classmapVersion': 'none',
        'productionArtifact': 'none',
        'precision': 'none',
        'quantization': false,
        'checksum': 'none',
        'minimumConfidence': 0.6,
        'preprocessingVersion': 'none',
      };

  void resetStream() => _fusion.reset();

  /// Single-shot photo inference for the capture-photo pipeline.
  ///
  /// [alignedRgb] is a model-size interleaved RGB crop
  /// (`inputWidth x inputHeight x 3`) prepared off the UI thread (see
  /// `fer_photo_pipeline.dart`); [quality]/[qualityDetails] carry the
  /// background-measured face quality. Runs the SAME tail as streaming
  /// frames — preprocessing contract, interpreter run, logits decoding,
  /// temperature calibration, confidence/margin gates — with no temporal
  /// fusion (a single photo has no frame sequence to smooth over).
  ///
  /// Throws [FerException] on infrastructure failure; returns quality-gated
  /// or UNCERTAIN results otherwise. Never invents an emotion.
  FerResult classifyPreparedFace({
    required Uint8List alignedRgb,
    required String alignMethod,
    required double eyeDistance,
    required double quality,
    required Map<String, double> qualityDetails,
    int framesAnalyzed = 1,
  }) {
    final manifest = _manifest;
    if (manifest == null || _interpreter == null) {
      throw FerException('NOT_LOADED', 'call load() before classify');
    }
    if (alignedRgb.length !=
        manifest.inputWidth * manifest.inputHeight * 3) {
      throw FerException('FRAME_SIZE_MISMATCH',
          'aligned crop ${alignedRgb.length} != '
          '${manifest.inputWidth}x${manifest.inputHeight}x3',);
    }
    final t0 = DateTime.now();
    return _inferAligned(
      aligned: AlignedRgbFace(alignedRgb, alignMethod, eyeDistance),
      quality: alignMethod == 'box' ? quality * 0.9 : quality,
      qualityDetails: qualityDetails,
      framesAnalyzed: framesAnalyzed,
      t0: t0,
      alignMs: 0,
      singleShot: true,
    );
  }

  /// Classify one frame.
  ///
  /// [grayFull] is the Y plane (W*H) in ML Kit's upright coordinate space and
  /// is used for the luminance-based quality gate only. [rgbFull] is the same
  /// frame converted to interleaved RGB (W*H*3) and is what the model sees.
  ///
  /// [singleShot]: photo-capture mode. The calibrated single-frame
  /// distribution is decided directly (same 0.60/0.10 gates) with NO temporal
  /// fusion — there is no frame sequence to smooth a single photo over, and
  /// requiring a multi-frame window for one capture would be an artificial
  /// delay, not reliability. A blink/mid-expression frame simply fails the
  /// gates and the user retakes. Defaults to false (continuous/streaming
  /// behavior unchanged).
  ///
  /// Throws [FerException] on infrastructure failure; returns quality-gated
  /// or UNCERTAIN results otherwise. Never invents an emotion.
  FerResult classifyFrame({
    required Uint8List grayFull,
    required Uint8List rgbFull,
    required int frameWidth,
    required int frameHeight,
    required List<Face> faces,
    required bool landmarksEnabled,
    int framesAnalyzed = 0,
    bool singleShot = false,
  }) {
    final manifest = _manifest;
    final itp = _interpreter;
    if (manifest == null || itp == null) {
      throw FerException('NOT_LOADED', 'call load() before classifyFrame');
    }
    if (grayFull.length != frameWidth * frameHeight) {
      throw FerException('FRAME_SIZE_MISMATCH',
          'gray ${grayFull.length} != $frameWidth*$frameHeight',);
    }
    if (rgbFull.length != frameWidth * frameHeight * 3) {
      throw FerException('FRAME_SIZE_MISMATCH',
          'rgb ${rgbFull.length} != $frameWidth*$frameHeight*3',);
    }
    final t0 = DateTime.now();

    if (faces.isEmpty) {
      if (kFerDiagnostics) {
        // ignore: avoid_print
        print('FER_DIAG f=$framesAnalyzed REJECT no_face');
      }
      return _noFace(manifest, framesAnalyzed);
    }
    if (faces.length > 1) {
      lowQualityTotal++;
      if (kFerDiagnostics) {
        // ignore: avoid_print
        print('FER_DIAG f=$framesAnalyzed REJECT multiple_faces '
            'n=${faces.length}');
      }
      return _statusOnly(
          manifest, FerStatus.multipleFaces, 0.0, framesAnalyzed, t0,);
    }

    final face = faces.first;
    final report = _gate.evaluate(
      face: face,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      grayFull: grayFull,
      landmarksEnabled: landmarksEnabled,
    );
    if (!report.passed) {
      lowQualityTotal++;
      if (kFerDiagnostics) {
        // ignore: avoid_print
        print('FER_DIAG f=$framesAnalyzed REJECT quality '
            'status=${report.status.wire} q=${report.quality.toStringAsFixed(2)} '
            '${report.details.entries.map((e) => '${e.key}=${e.value.toStringAsFixed(1)}').join(' ')}');
      }
      return _statusOnly(
          manifest, report.status, report.quality, framesAnalyzed, t0,
          qualityDetails: report.details,);
    }

    final swAlign = Stopwatch()..start();
    final aligned = _aligner.align(
      rgbFull: rgbFull,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      face: face,
    );
    final alignMs = swAlign.elapsedMilliseconds;
    profiler?.record(FerStage.faceCrop, alignMs.toDouble());
    return _inferAligned(
      aligned: aligned,
      quality: report.quality,
      qualityDetails: report.details,
      framesAnalyzed: framesAnalyzed,
      t0: t0,
      alignMs: alignMs,
      singleShot: singleShot,
    );
  }

  /// ROI fast path: the identical pipeline to [classifyFrame] for one
  /// already-cropped face region.
  ///
  /// All buffers/coordinates live in ML Kit's UPRIGHT space; [roiBox] and the
  /// eye points are ROI-relative (full-frame upright coords minus the ROI
  /// origin). [fullFrameWidth]/[fullFrameHeight] are the FULL upright frame
  /// dims and are used ONLY for the face-size ratio gate — statistics run on
  /// the small ROI buffers. Throws [FerException] on infrastructure failure;
  /// returns quality-gated or UNCERTAIN results otherwise. Never invents an
  /// emotion.
  FerResult classifyRoi({
    required Uint8List grayRoi,
    required int roiWidth,
    required int roiHeight,
    required Uint8List rgbRoi,
    required Rect roiBox,
    double? leftEyeX,
    double? leftEyeY,
    double? rightEyeX,
    double? rightEyeY,
    required double yawDeg,
    required double pitchDeg,
    required bool leftEyePresent,
    required bool rightEyePresent,
    required int fullFrameWidth,
    required int fullFrameHeight,
    required bool landmarksEnabled,
    int framesAnalyzed = 0,
  }) {
    final manifest = _manifest;
    final itp = _interpreter;
    if (manifest == null || itp == null) {
      throw FerException('NOT_LOADED', 'call load() before classifyRoi');
    }
    if (grayRoi.length != roiWidth * roiHeight) {
      throw FerException('FRAME_SIZE_MISMATCH',
          'gray ROI ${grayRoi.length} != $roiWidth*$roiHeight',);
    }
    if (rgbRoi.length != roiWidth * roiHeight * 3) {
      throw FerException('FRAME_SIZE_MISMATCH',
          'rgb ROI ${rgbRoi.length} != $roiWidth*$roiHeight*3',);
    }
    final t0 = DateTime.now();

    final report = _gate.evaluateBox(
      box: roiBox,
      yawDeg: yawDeg,
      pitchDeg: pitchDeg,
      leftEyePresent: leftEyePresent,
      rightEyePresent: rightEyePresent,
      frameWidth: roiWidth,
      frameHeight: roiHeight,
      sizeRefWidth: fullFrameWidth,
      sizeRefHeight: fullFrameHeight,
      grayFull: grayRoi,
      landmarksEnabled: landmarksEnabled,
    );
    if (!report.passed) {
      lowQualityTotal++;
      if (kFerDiagnostics) {
        // ignore: avoid_print
        print('FER_DIAG f=$framesAnalyzed REJECT roi-quality '
            'status=${report.status.wire} q=${report.quality.toStringAsFixed(2)}');
      }
      return _statusOnly(
          manifest, report.status, report.quality, framesAnalyzed, t0,
          qualityDetails: report.details,);
    }

    final swAlign = Stopwatch()..start();
    final aligned = _aligner.alignBox(
      rgbFull: rgbRoi,
      frameWidth: roiWidth,
      frameHeight: roiHeight,
      box: roiBox,
      leftEyeX: leftEyeX,
      leftEyeY: leftEyeY,
      rightEyeX: rightEyeX,
      rightEyeY: rightEyeY,
    );
    final alignMs = swAlign.elapsedMilliseconds;
    profiler?.record(FerStage.faceCrop, alignMs.toDouble());
    return _inferAligned(
      aligned: aligned,
      quality: report.quality,
      qualityDetails: report.details,
      framesAnalyzed: framesAnalyzed,
      t0: t0,
      alignMs: alignMs,
    );
  }

  /// Shared inference tail: preprocessing -> interpreter run -> logits
  /// handling (softmax when the artifact emits logits — NEVER treating logits
  /// as probabilities) -> calibration -> temporal fusion -> confidence-gated
  /// result. Used by both [classifyFrame] and [classifyRoi] so the two paths
  /// cannot diverge in output handling.
  ///
  /// [singleShot] (photo mode) skips temporal fusion and decides on the
  /// calibrated single-frame distribution with the same gates; the emitted
  /// label, confidence, margin and scores are measured on identical evidence
  /// either way.
  FerResult _inferAligned({
    required AlignedRgbFace aligned,
    required double quality,
    required Map<String, double> qualityDetails,
    required int framesAnalyzed,
    required DateTime t0,
    required int alignMs,
    bool singleShot = false,
  }) {
    final manifest = _manifest;
    final itp = _interpreter;
    if (manifest == null || itp == null) {
      throw FerException('NOT_LOADED', 'call load() before classifyFrame');
    }
    var fusedQuality = quality;
    if (aligned.method == 'box') fusedQuality *= 0.9; // reported, not hidden

    final swPre = Stopwatch()..start();
    final tensorBuf = _tensorBuf;
    final Object input;
    if (tensorBuf != null && !_quantized) {
      _pre.toTensorInputInto(aligned.pixels, tensorBuf, quantized: _quantized);
      input = tensorBuf;
    } else {
      input = _pre.toTensorInput(aligned.pixels, quantized: _quantized);
    }
    final preprocessMs = swPre.elapsedMilliseconds;
    profiler?.record(FerStage.preprocess, preprocessMs.toDouble());
    List<List<double>> output;
    try {
      inferenceTotal++;
      output = List.generate(
          1, (_) => List<double>.filled(manifest.classes.length, 0.0),);
      if (_quantized) {
        final outInts = List.generate(
            1, (_) => List<int>.filled(manifest.classes.length, 0),);
        itp.run(input, outInts);
        final t = itp.getOutputTensor(0);
        final q = t.params;
        final scale = q.scale, zeroPoint = q.zeroPoint;
        for (var i = 0; i < manifest.classes.length; i++) {
          output[0][i] = (outInts[0][i] - zeroPoint) * scale;
        }
      } else {
        // Pass the tensor as raw bytes, not as a flat Float32List.
        //
        // tflite_flutter infers an input shape from the Dart container and,
        // if it differs from the tensor's, calls resizeInputTensor. A flat
        // Float32List infers [150528], which does not match this model's fixed
        // [1,3,224,224] input, so the interpreter tried to resize a fixed-shape
        // tensor and failed with "Bad state: failed precondition" — which the
        // warm-up surfaced as WARMUP_FAILED on a real device. A Uint8List is
        // passed through byte-for-byte and short-circuits the shape check
        // entirely. The float32 little-endian bytes are identical either way.
        final flat = input as Float32List;
        final outBuf = Float32List(manifest.classes.length);
        final swInfer = Stopwatch()..start();
        itp.run(flat.buffer.asUint8List(), outBuf.buffer);
        _inferenceMicros = swInfer.elapsedMicroseconds;
        for (var i = 0; i < manifest.classes.length; i++) {
          output[0][i] = outBuf[i];
        }
      }
    } catch (e) {
      inferenceFailureTotal++;
      throw FerException('INFERENCE_FAILED', e.toString());
    }

    final probabilities = decodeOutput(output[0]);
    profiler?.record(FerStage.inference, _inferenceMicros / 1000.0);
    final swDecode = Stopwatch()..start();
    final calibrated = _cal.applyTemperature(probabilities);
    // Streaming: gate on the FUSED distribution, not the raw single frame.
    // The emitted label comes from [fused.vote], so confidence and margin
    // must be measured on the same evidence. Deciding on the raw frame threw
    // away the entire benefit of temporal fusion: a steady but noisy
    // expression failed the confidence gate even while the EMA was
    // confidently converged on it.
    // Photo (singleShot): no frame sequence exists, so the calibrated
    // single-frame distribution IS the evidence — same gates, no fusion.
    final FerTemporalState? fused =
        singleShot ? null : _fusion.addFrame(calibrated, fusedQuality);
    profiler?.record(FerStage.temporal, swDecode.elapsedMicroseconds / 1000.0);
    // The emitted label and the confidence/margin gate are measured on the
    // same evidence: the fused EMA vote in streaming mode, the calibrated
    // single frame in photo mode.
    final decision = singleShot || fused == null
        ? _cal.decide(calibrated)
        : _cal.decide(fused.ema);

    final scores = <String, double>{};
    for (var i = 0; i < manifest.classes.length; i++) {
      scores[manifest.classes[i]] = calibrated[i];
    }

    final certain = singleShot || fused == null
        ? decision.certain
        : (decision.certain && fused.stable);
    final topIndex =
        singleShot || fused == null ? decision.topIndex : fused.vote;
    final emotion = certain ? manifest.classes[topIndex] : 'unknown';
    if (!certain) unknownTotal++;
    if (kFerDiagnostics) {
      // Full 7-class decoded distribution BEFORE temporal fusion, plus the
      // raw tensor top-1 (proves whether the artifact emitted logits).
      // No pixels, labels+scalars only.
      // ignore: avoid_print
      print('FER_RAW f=$framesAnalyzed raw:${manifest.classes.map((c) => '$c=${(scores[c]! * 100).toStringAsFixed(1)}%').join(' ')} '
          'rawTop=${output[0][decision.topIndex].toStringAsFixed(2)} q=${fusedQuality.toStringAsFixed(2)}');
      // FER_DIAG: instrumentation to confirm WHY a class never surfaces.
      // Records the gate verdict per frame, not just the outcome. No pixels:
      // the previous version base64-encoded the face crop into logcat, which
      // is a privacy leak and is deliberately gone.
      final ranked = List<int>.generate(manifest.classes.length, (i) => i)
        ..sort((a, b) => calibrated[b].compareTo(calibrated[a]));
      final top3 = ranked
          .take(3)
          .map((i) =>
              '${manifest.classes[i]}=${calibrated[i].toStringAsFixed(2)}',)
          .join(' ');
      // ignore: avoid_print
      print('FER_DIAG f=$framesAnalyzed q=${fusedQuality.toStringAsFixed(2)} '
          'top:$top3 conf=${decision.confidence.toStringAsFixed(3)} '
          'margin=${decision.margin.toStringAsFixed(3)} '
          'vote=${manifest.classes[topIndex]} '
          'agree=${fused == null ? 1.0 : fused.agreement} '
          'frames=${fused?.frames ?? 1} stable=${fused?.stable ?? true} '
          'certain=$certain '
          'fail=${decision.certain ? ((fused == null || fused.stable) ? "" : "TEMPORAL") : "CONFIDENCE"}');
    }
    final latency = DateTime.now().difference(t0).inMilliseconds;
    latencyMsSamples.add(latency);
    if (latencyMsSamples.length > 200) latencyMsSamples.removeAt(0);

    final va = _valenceArousal(scores);
    final decodeMs = swDecode.elapsedMilliseconds;
    profiler?.record(FerStage.postprocess, decodeMs.toDouble());
    return FerResult(
      emotion: emotion,
      scores: scores,
      calibratedConfidence: decision.confidence,
      rawTopProbability: probabilities[decision.topIndex],
      margin: decision.margin,
      faceQuality: fusedQuality,
      status: certain ? FerStatus.predicted : FerStatus.uncertain,
      modelId: manifest.modelId,
      modelVersion: manifest.version,
      preprocessingVersion: manifest.preprocessingVersion,
      valence: va[0],
      arousal: va[1],
      framesAnalyzed: framesAnalyzed,
      delegate: _delegate,
      latencyMs: latency,
      qualityDetails: {
        ...qualityDetails,
        'eyeDistance': aligned.eyeDistance,
        'temporalAgreement': fused?.agreement ?? 1.0,
        'temporalFrames': (fused?.frames ?? 1).toDouble(),
      },
      timings: {
        'align': alignMs,
        'preprocess': preprocessMs,
        'inference': _inferenceMicros ~/ 1000,
        'decode': decodeMs,
      },
    );
  }

  FerResult _noFace(FerManifest m, int frames) => FerResult(
        emotion: 'unknown',
        scores: {for (final c in m.classes) c: 0.0},
        calibratedConfidence: 0.0,
        rawTopProbability: 0.0,
        margin: 0.0,
        faceQuality: 0.0,
        status: FerStatus.noFace,
        modelId: m.modelId,
        modelVersion: m.version,
        preprocessingVersion: m.preprocessingVersion,
        valence: 0.0,
        arousal: 0.0,
        framesAnalyzed: frames,
        delegate: _delegate,
      );

  FerResult _statusOnly(
          FerManifest m, FerStatus s, double q, int frames, DateTime t0,
          {Map<String, double> qualityDetails = const {},}) =>
      FerResult(
        emotion: 'unknown',
        scores: {for (final c in m.classes) c: 0.0},
        calibratedConfidence: 0.0,
        rawTopProbability: 0.0,
        margin: 0.0,
        faceQuality: q,
        status: s,
        modelId: m.modelId,
        modelVersion: m.version,
        preprocessingVersion: m.preprocessingVersion,
        valence: 0.0,
        arousal: 0.0,
        framesAnalyzed: frames,
        delegate: _delegate,
        latencyMs: DateTime.now().difference(t0).inMilliseconds,
        qualityDetails: qualityDetails,
      );

  /// Affective projection (valence/arousal), v1 for the 7-class model.
  /// Non-clinical display signal only — never a diagnosis input.
  ///
  /// Keyed on the new canonical ids ('happy'/'sad', no 'contempt' class). A
  /// missing key falls back to 0 rather than null so a renamed class can
  /// never produce NaN downstream.
  List<double> _valenceArousal(Map<String, double> s) {
    double g(String k) => s[k] ?? 0.0;
    final valence = g('happy') * 1.0 +
        g('surprise') * 0.3 -
        g('sad') * 0.8 -
        g('anger') * 0.9 -
        g('fear') * 0.7 -
        g('disgust') * 0.6;
    final arousal = g('anger') * 0.8 +
        g('surprise') * 0.9 +
        g('fear') * 0.7 +
        g('happy') * 0.3 -
        g('neutral') * 0.3 -
        g('sad') * 0.4;
    return [valence.clamp(-1.0, 1.0), arousal.clamp(-1.0, 1.0)];
  }

  Future<void> _close(Interpreter itp) async {
    try {
      itp.close();
    } catch (_) {}
  }

  void dispose() {
    if (_interpreter != null) {
      try {
        _interpreter!.close();
      } catch (_) {}
      _interpreter = null;
    }
    if (_gpuDelegate != null) {
      try {
        _gpuDelegate!.delete();
      } catch (_) {}
      _gpuDelegate = null;
    }
    _manifest = null;
    _tensorBuf = null;
    _modelBlob = null; // releases the memory-mapped model buffer
    _delegate = 'cpu';
    _delegateReason = 'disposed';
  }

  /// Bytes held across frames (model mapping is native-side and excluded;
  /// this tracks the Dart-side reusable buffers whose growth indicates a
  /// leak). Fed to [FerPipelineProfiler.estimatedLiveBytes].
  int _estimateLiveBytes() {
    var bytes = 0;
    final t = _tensorBuf;
    if (t != null) bytes += t.lengthInBytes;
    final m = _manifest;
    if (m != null) {
      // aligner output + preprocessing scratch (peak, reused).
      bytes += m.inputWidth * m.inputHeight * 3; // aligned RGB crop
      bytes += m.classes.length * 8; // EMA window entry scale
    }
    return bytes;
  }
}
