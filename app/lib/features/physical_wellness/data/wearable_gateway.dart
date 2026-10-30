import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a BLE scan for nearby watches.
@immutable
class WearableScanResult {
  const WearableScanResult({
    required this.deviceIdentifier,
    required this.name,
    this.rssi = 0,
  });

  final String deviceIdentifier;
  final String name;
  final int rssi;

  factory WearableScanResult.fromJson(Map<String, dynamic> json) =>
      WearableScanResult(
        deviceIdentifier: json['deviceIdentifier'] as String? ?? '',
        name: json['name'] as String? ?? '',
        rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      );
}

/// One decoded reading taken off the watch in a single session.
@immutable
class WearableReading {
  const WearableReading({
    required this.metricType,
    required this.value,
    required this.timestamp,
    this.unit,
    this.measurementType,
  });

  final String metricType;
  final double value;
  final DateTime timestamp;
  final String? unit;
  final String? measurementType;
}

/// Everything the native layer decoded from one connect-and-read session.
///
/// Fields mirror the Kotlin `readSnapshot()` map exactly. Nulls mean the
/// device genuinely reported no data for that category — never placeholders.
@immutable
class WearableSnapshot {
  const WearableSnapshot({
    required this.deviceIdentifier,
    required this.recordedAt,
    this.firmwareVersion,
    this.batteryLevel,
    this.charging,
    this.capabilities = const [],
    this.capabilityReport = const [],
    this.readings = const [],
    this.dailyActivity,
    this.dailyActivities = const [],
    this.sleepSessions = const [],
    this.exerciseSessions = const [],
    this.framesReceived = 0,
    this.dataComplete = true,
  });

  final String deviceIdentifier;
  final String? firmwareVersion;
  final int? batteryLevel;
  final bool? charging;

  /// Legacy metric-name list (`capabilities`) kept for older native builds.
  final List<String> capabilities;

  /// What the session actually observed, ready for
  /// `PUT /wearables/{id}/capabilities`. Entries are never marked verified by
  /// the client; the server owns verification.
  final List<Map<String, dynamic>> capabilityReport;
  final List<WearableReading> readings;
  final Map<String, dynamic>? dailyActivity;

  /// One row per band-local date, from a multi-day history fetch. Prefer this
  /// over [dailyActivity], which is the legacy single-row field.
  final List<Map<String, dynamic>> dailyActivities;
  final List<Map<String, dynamic>> sleepSessions;
  final List<Map<String, dynamic>> exerciseSessions;
  final DateTime recordedAt;

  /// Protocol frames the band actually streamed during the session.
  final int framesReceived;

  /// False when the band acknowledged the link but streamed no history —
  /// an empty read must never be enqueued as a successful sync. Older native
  /// builds do not send this flag; absence is treated as true, but the
  /// controller still refuses to enqueue a snapshot without any metric data.
  final bool dataComplete;

  /// Whether the session produced at least one real metric record.
  bool get hasMetricData =>
      readings.isNotEmpty ||
      dailyActivity != null ||
      dailyActivities.isNotEmpty ||
      sleepSessions.isNotEmpty ||
      exerciseSessions.isNotEmpty;

  factory WearableSnapshot.fromJson(Map<String, dynamic> json) {
    final readings = <WearableReading>[];
    for (final item in (json['readings'] as List?) ?? const []) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final value = (map['value'] as num?)?.toDouble();
      final timestamp = DateTime.tryParse(map['timestamp']?.toString() ?? '');
      if (value == null || timestamp == null) continue;
      readings.add(
        WearableReading(
          metricType: map['metricType'] as String? ?? '',
          value: value,
          timestamp: timestamp,
          unit: map['unit'] as String?,
          measurementType: map['measurementType'] as String?,
        ),
      );
    }

    final daily = json['dailyActivity'];
    final dailyList = <Map<String, dynamic>>[];
    for (final item in (json['dailyActivities'] as List?) ?? const []) {
      if (item is Map) dailyList.add(item.cast<String, dynamic>());
    }
    if (dailyList.isEmpty && daily is Map) {
      dailyList.add(daily.cast<String, dynamic>());
    }
    final sleeps = <Map<String, dynamic>>[];
    for (final item in (json['sleepSessions'] as List?) ?? const []) {
      if (item is Map) sleeps.add(item.cast<String, dynamic>());
    }
    final exercises = <Map<String, dynamic>>[];
    for (final item in (json['exerciseSessions'] as List?) ?? const []) {
      if (item is Map) exercises.add(item.cast<String, dynamic>());
    }
    final report = <Map<String, dynamic>>[];
    for (final item in (json['capabilityReport'] as List?) ?? const []) {
      if (item is Map) report.add(item.cast<String, dynamic>());
    }

    return WearableSnapshot(
      deviceIdentifier: json['deviceIdentifier'] as String? ?? '',
      firmwareVersion: json['firmwareVersion'] as String?,
      batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
      charging: json['charging'] as bool?,
      capabilities: [
        for (final item in (json['capabilities'] as List?) ?? const [])
          item.toString(),
      ],
      capabilityReport: report,
      readings: readings,
      dailyActivity: daily is Map ? daily.cast<String, dynamic>() : null,
      dailyActivities: dailyList,
      sleepSessions: sleeps,
      exerciseSessions: exercises,
      recordedAt: DateTime.tryParse(json['recordedAt']?.toString() ?? '') ??
          DateTime.now(),
      framesReceived: (json['framesReceived'] as num?)?.toInt() ?? 0,
      dataComplete: json['dataComplete'] as bool? ?? true,
    );
  }
}

/// One live heart-rate sample streamed while a monitor session runs.
///
/// Every field comes off the band's own frame or the host receipt clock;
/// nothing is interpolated between samples, and an idle sensor produces
/// no event at all rather than a placeholder reading.
@immutable
class LiveHeartRateSample {
  const LiveHeartRateSample({
    required this.bpm,
    required this.timestamp,
    required this.recordedAt,
    this.spo2,
    this.deviceIdentifier,
    this.source,
    this.measurementType,
  });

  /// Beats per minute as measured by the band.
  final int bpm;

  /// Blood-oxygen percentage from the same band frame, when the optical
  /// sensor reported a physiologically plausible value (50–100). Null means
  /// the frame carried no SpO2 measurement, never a guessed value.
  final int? spo2;

  /// Measurement time derived from the band's seconds-of-day field.
  final DateTime timestamp;

  /// Host receipt time (UTC) — when the sample reached the phone.
  final DateTime recordedAt;

  final String? deviceIdentifier;
  final String? source;
  final String? measurementType;

  factory LiveHeartRateSample.fromJson(Map<String, dynamic> json) {
    final bpm = (json['bpm'] as num?)?.toInt();
    final timestamp =
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now().toUtc();
    final recordedAt =
        DateTime.tryParse(json['recordedAt']?.toString() ?? '') ??
            DateTime.now().toUtc();
    if (bpm == null) {
      throw const FormatException('heart-rate event without bpm');
    }
    return LiveHeartRateSample(
      bpm: bpm,
      timestamp: timestamp,
      recordedAt: recordedAt,
      spo2: switch ((json['spo2'] as num?)?.toInt()) {
        final int value when value >= 50 && value <= 100 => value,
        _ => null,
      },
      deviceIdentifier: json['deviceIdentifier'] as String?,
      source: json['source'] as String?,
      measurementType: json['measurementType'] as String?,
    );
  }
}

/// Contract between the Dart layer and the native BLE implementation.
///
/// Production uses [MethodChannelWearableGateway]; tests inject in-memory
/// fakes. Calls degrade gracefully only when the platform channel is absent
/// (widget tests, desktop runs: [MissingPluginException] → safe defaults).
/// Genuine native failures arrive as [WearableException] carrying the
/// platform error code (`BLUETOOTH_OFF`, `PERMISSION_REQUIRED`,
/// `SCAN_FAILED`, `NOT_CONNECTED`, `BUSY`, …) so callers can show an
/// actionable message instead of misreporting the failure.
abstract class WearableGateway {
  /// Whether the native BLE stack exists on this platform.
  Future<bool> isAvailable();

  /// Adapter state: `'on'`, `'off'`, `'unsupported'`, or `'unknown'` when the
  /// platform side is absent. Has a default body so existing fakes keep
  /// compiling; the method-channel implementation overrides it.
  Future<String> bluetoothState() async => 'unknown';

  Future<bool> hasPermissions();

  /// Prompts for location + nearby-devices permission. Returns the result.
  Future<bool> requestPermissions();

  /// Scans for nearby watches for [timeout] and returns what it found.
  Future<List<WearableScanResult>> scan({
    Duration timeout = const Duration(seconds: 6),
  });

  Future<bool> connect(String deviceIdentifier);

  Future<void> disconnect();

  /// Reads and decodes the watch's history in one session, or null when
  /// no device is connected / the platform has no BLE.
  Future<WearableSnapshot?> readSnapshot();

  /// Starts continuous heart-rate measurement on the connected band.
  ///
  /// Returns `true` when the command sequence reached the radio; whether the
  /// sensor then produces samples is the band's call (see [liveHeartRate]).
  /// Default `false` keeps existing fakes compiling and degrades honestly to
  /// "no live monitoring here".
  Future<bool> startHeartRateMonitor() async => false;

  /// Stops measurement. Returns `true` when an active session was stopped.
  Future<bool> stopHeartRateMonitor() async => false;

  /// Live samples emitted while a monitor session runs. Empty when the
  /// platform has no BLE — never populated with synthetic data.
  Stream<LiveHeartRateSample> get liveHeartRate => const Stream.empty();
}

/// A genuine failure reported by the native BLE layer.
///
/// [code] mirrors the platform error code (`BLUETOOTH_OFF`,
/// `PERMISSION_REQUIRED`, `SCAN_FAILED`, `NOT_CONNECTED`, `BUSY`,
/// `BAD_ARGUMENT`, …); [message] is the human-readable detail.
class WearableException implements Exception {
  const WearableException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'WearableException($code${message == null ? '' : ': $message'})';
}

/// Picks the most likely watch out of raw scan results.
///
/// BLE scans see every nearby peripheral (headphones, beacons, TVs). Only a
/// device whose advertised name looks like a wrist wearable is treated as a
/// connection candidate; anything else is left alone so the app never pairs
/// with a random peripheral. Returns null when nothing compatible was seen.
class WearableCompatibility {
  static final RegExp _watchName = RegExp(
    r'watch|band|fitpro|amazfit|gts|gtr|bip|galaxy|garmin|huawei|honor|redmi|xiaomi|realme|noise|boat|fire-?boltt|fossil|ticwatch|pixel|apple|versa|sense|charge|inspire|luxe|mi_|zepp|coros|suunto|polar|withings|oneplus|oppo|vivo|nothing',
    caseSensitive: false,
  );

  /// Strongest-signal compatible candidate first; null when none qualifies.
  static WearableScanResult? pickCandidate(List<WearableScanResult> results) {
    final compatible = [
      for (final r in results)
        if (r.deviceIdentifier.isNotEmpty && _watchName.hasMatch(r.name)) r,
    ];
    if (compatible.isEmpty) return null;
    compatible.sort((a, b) => b.rssi.compareTo(a.rssi));
    return compatible.first;
  }
}

/// First MethodChannel in the app: bridges to `MainActivity.kt`'s
/// `mindease/wearable` channel where the FitPro GATT client lives.
class MethodChannelWearableGateway implements WearableGateway {
  MethodChannelWearableGateway();

  static const MethodChannel _channel = MethodChannel('mindease/wearable');
  static const EventChannel _events = EventChannel('mindease/wearable/events');

  /// Invokes the platform side. A missing plugin (desktop, widget tests)
  /// degrades to null so callers fall back to safe defaults; any real
  /// platform error is rethrown as a [WearableException] with its code.
  Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw WearableException(e.code, e.message);
    }
  }

  @override
  Future<bool> isAvailable() async =>
      await _invoke<bool>('isAvailable') ?? false;

  @override
  Future<String> bluetoothState() async =>
      await _invoke<String>('bluetoothState') ?? 'unknown';

  @override
  Future<bool> hasPermissions() async =>
      await _invoke<bool>('hasPermissions') ?? false;

  @override
  Future<bool> requestPermissions() async =>
      await _invoke<bool>('requestPermissions') ?? false;

  @override
  Future<List<WearableScanResult>> scan({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final raw =
        await _invoke<List>('scan', {'timeoutMillis': timeout.inMilliseconds});
    final results = <WearableScanResult>[];
    for (final item in raw ?? const []) {
      if (item is Map) {
        results.add(
          WearableScanResult.fromJson(item.cast<String, dynamic>()),
        );
      }
    }
    return results;
  }

  @override
  Future<bool> connect(String deviceIdentifier) async =>
      await _invoke<bool>('connect', {'deviceIdentifier': deviceIdentifier}) ??
      false;

  @override
  Future<void> disconnect() => _invoke<void>('disconnect');

  @override
  Future<WearableSnapshot?> readSnapshot() async {
    final raw = await _invoke<Map>('readSnapshot');
    if (raw == null) return null;
    return WearableSnapshot.fromJson(raw.cast<String, dynamic>());
  }

  @override
  Future<bool> startHeartRateMonitor() async =>
      await _invoke<bool>('startHeartRateMonitor') ?? false;

  @override
  Future<bool> stopHeartRateMonitor() async =>
      await _invoke<bool>('stopHeartRateMonitor') ?? false;

  /// Broadcast stream of band-emitted samples. A missing plugin (widget
  /// tests, desktop) is swallowed so the stream simply stays idle; control
  /// events (`monitorStopped`) are filtered out, and genuine native errors or
  /// malformed heart-rate events surface as stream errors the caller must
  /// handle — they are never converted into fake data.
  ///
  /// A fresh stream is created per call: `_liveSamples()` is an `async*`
  /// (single-subscription) stream, so caching it would make a second
  /// Start/Stop cycle throw "Stream has already been listened to".
  @override
  Stream<LiveHeartRateSample> get liveHeartRate => _liveSamples();

  Stream<LiveHeartRateSample> _liveSamples() async* {
    try {
      await for (final event in _events.receiveBroadcastStream()) {
        if (event is! Map || event['event'] != 'heartRate') continue;
        yield LiveHeartRateSample.fromJson(event.cast<String, dynamic>());
      }
    } on MissingPluginException {
      // No native BLE stack here (widget tests, desktop): the stream stays
      // idle instead of inventing readings.
      return;
    }
  }
}
