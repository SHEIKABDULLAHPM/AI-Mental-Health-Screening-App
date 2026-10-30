import 'fer_classifier.dart';

/// App-session warm holder for the FER interpreter.
///
/// Root cause it addresses: the 172 MB model costs ~16 s to load
/// (asset read + checksum + delegate probe + warm-up), and every fresh
/// camera-screen open paid it in full — including retries and re-entries.
/// Warming starts while the user answers the surrounding mood questions, so
/// the camera screen usually opens warm and time-to-first-result drops to
/// the stabilization window alone (~2–4 s).
///
/// Ownership is transferred, never shared: [take] hands the single ready
/// instance to one screen (holder forgets it) and that screen owns disposal
/// exactly as before. A screen opened without a warm instance loads its own
/// through the unchanged path. Warm-up failures are swallowed — the normal
/// load path remains the fallback, so prewarming can never break the flow.
class FerPreloader {
  FerPreloader._();

  static Future<void>? _warming;
  static FerClassifier? _warm;

  /// Starts a one-time background load. Idempotent: concurrent calls while a
  /// load is in flight or a warm instance waits are no-ops. Never throws.
  static void warmup() {
    if (_warm != null || _warming != null) return;
    _warming = _load();
  }

  static Future<void> _load() async {
    try {
      final c = FerClassifier();
      await c.load(manifestAsset: 'assets/models/vit_fer_manifest.json');
      if (c.isReady) {
        _warm = c;
      } else {
        c.dispose();
      }
    } catch (_) {
      // Fall through: the camera screen loads its own interpreter.
    } finally {
      _warming = null;
    }
  }

  /// Takes the warm instance for exclusive ownership, or null when none is
  /// ready yet. The taker must dispose it (the camera screen already does).
  static FerClassifier? take() {
    final c = _warm;
    _warm = null;
    return (c != null && c.isReady) ? c : null;
  }
}
