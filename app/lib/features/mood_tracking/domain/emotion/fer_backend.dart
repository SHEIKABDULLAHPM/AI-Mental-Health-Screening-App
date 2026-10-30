/// Acceleration-backend selection for the FER interpreter.
///
/// Probing order (each backend tested independently, exactly once per
/// process):
///
///   GPU (GpuDelegateV2) -> NNAPI -> CPU/XNNPACK (threads = 4)
///
/// Rules enforced here so callers cannot get them wrong:
///
/// - A failing GPU delegate is created at most ONCE per process, logged
///   ONCE, deleted, and never retried. Repeatedly recreating a delegate
///   that throws on SM-M325F (Mali-G52) is pure startup latency.
/// - If GPU is unsupported: fail gracefully, record the reason, fall back
///   to NNAPI or CPU and continue without crashing.
/// - Never assume GPU is faster: the selected backend and the measured
///   warm-up latency of every attempted backend are reported via
///   [FerBackendOffer] so the FER_BENCH / FER_PERF logs show real numbers.
/// - CPU uses 4 threads (Exynos 850 in SM-M325F is 8x Cortex-A55; 4 threads
///   saturates the big-cluster-equivalent throughput for a memory-bound ViT
///   without oversubscribing). Thread count is a parameter for benchmarking.
library;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Acceleration backend chosen for one interpreter instance.
enum FerBackendKind { gpu, nnapi, cpu }

/// Result of probing/creating an interpreter for a model buffer.
class FerBackendOffer {
  const FerBackendOffer({
    required this.interpreter,
    required this.backend,
    required this.label,
    required String reason,
    required this.attemptLatenciesMs,
    this.gpuDelegate,
  }) : _reason = reason;

  /// Ready-to-use interpreter. Ownership passes to the caller, which must
  /// close it (and delete [gpuDelegate] when non-null) on dispose/fallback.
  final Interpreter interpreter;
  final FerBackendKind backend;

  /// Short backend id for logs/payloads ('gpu' | 'nnapi' | 'cpu').
  final String label;

  /// Why this backend was selected (e.g. 'gpu_unsupported: ...' / 'gpu_ok').
  String get reason => _reason;
  final String _reason;

  /// Measured interpreter-creation (+ warm-up, when [warmUp] ran) latency
  /// per attempted backend, in milliseconds. The benchmark evidence that the
  /// selected backend is actually the fastest on THIS device.
  final Map<String, int> attemptLatenciesMs;

  final Delegate? gpuDelegate;
}

/// Creates the FER interpreter with GPU -> NNAPI -> CPU fallback.
///
/// [modelBytes] must stay alive for the interpreter's lifetime (the
/// interpreter memory-maps the buffer; do not discard it while in use).
///
/// [warmUp] runs a zero-input inference to prove the selected delegate can
/// EXECUTE the graph (a delegate that creates cleanly but fails at run time
/// must trigger fallback here, never mid-session). Keep the default true.
///
/// [quantized] selects the warm-up output container type.
class FerBackendProbe {
  /// Process-wide latch: the GPU delegate failed before (typical on Mali).
  /// Never pay delegate-creation cost again in this process.
  static bool _gpuKnownBad = false;
  static String? _gpuFailureReason;
  static bool _failureLogged = false;

  static bool get gpuKnownBad => _gpuKnownBad;
  static String? get gpuFailureReason => _gpuFailureReason;

  /// For tests: reset the process-wide GPU latch.
  @visibleForTesting
  static void resetForTest() {
    _gpuKnownBad = false;
    _gpuFailureReason = null;
    _failureLogged = false;
  }

  /// Probe backends in order and return the first working interpreter.
  ///
  /// Throws [StateError] only when NO backend can create an interpreter
  /// (out of memory / corrupt model) — GPU-unsupported alone never throws.
  static Future<FerBackendOffer> create({
    required Uint8List modelBytes,
    required int outputClasses,
    required bool quantized,
    int cpuThreads = 4,
    bool tryGpu = true,
    bool tryNnapi = true,
    bool Function()? isDisposed,
    Future<void> Function(Interpreter interpreter, bool quantized)? warmUp,
  }) async {
    final attempts = <String, int>{};
    final disposed = isDisposed ?? () => false;

    // 1) GPU — attempted at most once per process.
    if (tryGpu && !_gpuKnownBad && !disposed()) {
      final sw = Stopwatch()..start();
      Delegate? gpu;
      Interpreter? itp;
      try {
        final opts = InterpreterOptions()..threads = 2;
        gpu = GpuDelegateV2();
        opts.addDelegate(gpu);
        itp = Interpreter.fromBuffer(modelBytes, options: opts);
        if (warmUp != null) await warmUp(itp, quantized);
        attempts['gpu'] = sw.elapsedMilliseconds;
        return FerBackendOffer(
          interpreter: itp,
          backend: FerBackendKind.gpu,
          label: 'gpu',
          reason: 'gpu_ok',
          attemptLatenciesMs: attempts,
          gpuDelegate: gpu,
        );
      } catch (e) {
        attempts['gpu'] = sw.elapsedMilliseconds;
        _gpuKnownBad = true;
        _gpuFailureReason = '${e.runtimeType}: $e';
        // Log exactly once per process — every load retry would otherwise
        // spam logcat with the same Mali failure.
        if (!_failureLogged) {
          _failureLogged = true;
          debugPrint('FER_PERF gpu_delegate_failed_once $_gpuFailureReason');
        }
        try {
          gpu?.delete();
        } catch (_) {}
        if (itp != null) {
          try {
            itp.close();
          } catch (_) {}
        }
      }
    } else if (_gpuKnownBad && tryGpu) {
      attempts['gpu'] = -1; // skipped: known-bad, not retried
    }

    // 2) NNAPI — the realistic accelerated path on Exynos when GPU is out.
    // ViT graphs often lack full NNAPI op coverage, so failure here is a
    // normal, handled outcome — not an error.
    if (tryNnapi && !disposed()) {
      final sw = Stopwatch()..start();
      try {
        final opts = InterpreterOptions()
          ..threads = cpuThreads
          ..useNnApiForAndroid = true;
        final itp = Interpreter.fromBuffer(modelBytes, options: opts);
        if (warmUp != null) await warmUp(itp, quantized);
        attempts['nnapi'] = sw.elapsedMilliseconds;
        return FerBackendOffer(
          interpreter: itp,
          backend: FerBackendKind.nnapi,
          label: 'nnapi',
          reason: _gpuKnownBad
              ? 'gpu_unsupported(${_gpuFailureReason ?? 'unknown'})→nnapi_ok'
              : 'nnapi_ok',
          attemptLatenciesMs: attempts,
        );
      } catch (e) {
        attempts['nnapi'] = sw.elapsedMilliseconds;
        debugPrint('FER_PERF nnapi_unsupported ${e.runtimeType}: $e');
      }
    }

    // 3) CPU/XNNPACK — the guaranteed path. Never throws for delegate
    // reasons; throws only when the model itself cannot be instantiated.
    if (!disposed()) {
      final sw = Stopwatch()..start();
      final opts = InterpreterOptions()..threads = cpuThreads;
      final itp = Interpreter.fromBuffer(modelBytes, options: opts);
      if (warmUp != null) await warmUp(itp, quantized);
      attempts['cpu'] = sw.elapsedMilliseconds;
      final why = _gpuKnownBad
          ? 'gpu_unsupported(${_gpuFailureReason ?? 'unknown'})→cpu_ok'
          : 'cpu_ok';
      return FerBackendOffer(
        interpreter: itp,
        backend: FerBackendKind.cpu,
        label: 'cpu',
        reason: why,
        attemptLatenciesMs: attempts,
      );
    }

    throw StateError('FER interpreter creation aborted (owner disposed)');
  }
}
