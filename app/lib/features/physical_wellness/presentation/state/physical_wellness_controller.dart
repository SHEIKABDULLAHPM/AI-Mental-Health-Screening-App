import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/physical_wellness/data/physical_local_cache.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_api.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_models.dart';
import 'package:mindease/features/physical_wellness/data/wearable_gateway.dart';

/// Drives the Physical Wellness dashboard: today's metrics (offline-first),
/// weekly trend, device pairing, and the durable sync queue.
///
/// Sync is enqueue-first: every snapshot read off the watch is persisted to
/// [PhysicalLocalCache] before the network call, so a failed upload is
/// retried on the next `init()` instead of losing the user's history.
class PhysicalWellnessController extends ChangeNotifier {
  PhysicalWellnessController(
    this._api, {
    required WearableGateway gateway,
    required PhysicalLocalCache cache,
  })  : _gateway = gateway,
        _cache = cache;

  final PhysicalWellnessApi _api;
  final WearableGateway _gateway;
  final PhysicalLocalCache _cache;

  PhysicalToday? _today;
  WeeklySummary? _summary;
  WearableDevice? _device;
  bool _loading = false;
  bool _syncing = false;
  bool _connecting = false;
  bool _offline = false;
  bool _disposed = false;
  String? _error;
  String? _notice;
  int _pendingBatches = 0;
  /// Guards the once-per-app-session automatic synchronize. Opening the
  /// dashboard refreshes paired-watch data by itself; navigating back and
  /// forth within the same session must not retrigger BLE activity.
  bool _autoSyncAttempted = false;
  /// Last successful watch read; used by the screen-scoped periodic refresh.
  DateTime? _lastSyncAt;
  /// True between a successful live-HR start and its stop, so an automatic
  /// background fetch never interleaves a second preamble with the monitor.
  bool _monitorActive = false;

  PhysicalToday? get today => _today;
  WeeklySummary? get summary => _summary;
  WearableDevice? get device => _device;
  bool get loading => _loading;
  bool get syncing => _syncing;
  bool get connecting => _connecting;
  bool get offline => _offline;
  String? get error => _error;
  String? get notice => _notice;
  int get pendingBatches => _pendingBatches;

  /// Single entry point the screen calls from `initState`.
  Future<void> init() async {
    final cached = await _cache.readToday();
    final cachedDevice = await _cache.readDevice();
    if (cached != null) _today = cached;
    if (cachedDevice != null) _device = cachedDevice;
    _pendingBatches = (await _cache.readQueue()).length;
    _deferNotify();
    await Future.wait([loadToday(), loadSummary(), flushQueue()]);
    // A paired watch is fetched automatically once per app session. The
    // pipeline is quiet here: Bluetooth/permission gaps or a sleeping band
    // must not replace the dashboard's just-loaded state with a warning
    // banner; "Sync now" and pairing surface their failures explicitly.
    if (_device != null && !_autoSyncAttempted) {
      _autoSyncAttempted = true;
      unawaited(_autoSyncFromWatch());
    }
  }

  /// One automatic read per session for an already-paired watch. Skips
  /// silently when Bluetooth is off, permissions are missing or the gateway
  /// is unavailable — those require user action and belong to the pairing
  /// flow, not a background refresh.
  Future<void> _autoSyncFromWatch() async {
    try {
      final state = await _gateway.bluetoothState();
      if (state != 'on') return;
      if (!await _gateway.isAvailable()) return;
      if (!await _gateway.hasPermissions()) return;
    } on Object {
      return;
    }
    await _runDeviceSync(attemptReconnect: true, userVisible: false);
  }

  /// Recovery entry point the screen calls when the app returns to the
  /// foreground: retries queued batches (e.g. uploaded while the OS froze
  /// the BLE session in background) and refreshes the dashboard. Deliberately
  /// does NOT rescan or reconnect — a foreground resume must never trigger
  /// surprise Bluetooth activity or battery drain.
  Future<void> onForeground() async {
    await flushQueue();
    await Future.wait([loadToday(), loadSummary()]);
  }

  // ── Loading ────────────────────────────────────────────────────────────

  /// Offline-first "today": paints from cache, then upgrades from the
  /// network; a network failure with a cache hit degrades silently to the
  /// stale view (marked `offline`), and only a failure with no cache at all
  /// surfaces as an error.
  Future<void> loadToday() async {
    _start();
    final cached = _today ?? await _cache.readToday();
    if (cached != null) {
      _today = cached;
      _deferNotify();
    }
    try {
      final body = await _api.getPhysicalToday();
      _today = PhysicalToday.fromJson(body);
      _offline = false;
      _error = null;
      await _cache.writeToday(_today!);
      _loading = false;
      notifyListeners();
    } catch (e) {
      // The stale view is marked offline; log why so the banner is
      // diagnosable instead of looking like a dead backend.
      if (kDebugMode) {
        debugPrint('[physical] today refresh failed: $e');
      }
      if (_today == null) {
        _fail(e);
      } else {
        _offline = true;
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Weekly trend is best-effort: when it fails the dashboard still shows
  /// today, so the failure is absorbed into an absent section.
  Future<void> loadSummary() async {
    try {
      _summary = WeeklySummary.fromJson(await _api.getPhysicalSummary());
      if (!_disposed) notifyListeners();
    } on Object {
      _summary = null;
    }
  }

  // ── Device pairing ─────────────────────────────────────────────────────

  /// Scans for a watch, registers it with the backend, and remembers it.
  ///
  /// Every failure maps to an actionable notice: Bluetooth off, unsupported
  /// hardware, missing permission, scan problems, incompatible peripherals,
  /// and connection failures each explain what to do next instead of
  /// collapsing into a generic "not found".
  Future<void> connectDevice({
    Duration scanTimeout = const Duration(seconds: 6),
  }) async {
    if (_connecting) return;
    _connecting = true;
    _notice = null;
    _error = null;
    notifyListeners();
    try {
      final state = await _gateway.bluetoothState();
      if (state == 'unsupported') {
        _setNotice('This device does not support Bluetooth Low Energy.');
        return;
      }
      if (state == 'off') {
        _setNotice('Bluetooth is turned off. Turn it on to find your watch.');
        return;
      }
      if (!await _gateway.isAvailable()) {
        _setNotice(
          state == 'unknown'
              ? 'Bluetooth is not available on this device.'
              : 'Bluetooth is turned off. Turn it on to find your watch.',
        );
        return;
      }
      var granted = await _gateway.hasPermissions();
      if (!granted) {
        // Rationale first: the OS dialog says little, so the user learns
        // *why* access is needed before it appears. A grant overwrites this
        // with the outcome; a denial overwrites it with Settings guidance.
        _setNotice(
          'To find your watch, allow Bluetooth and nearby-device access when asked.',
        );
        granted = await _gateway.requestPermissions();
      }
      if (!granted) {
        _setNotice(
          'Bluetooth permission is required to find your watch. '
          'Allow nearby-device access in Settings, then try again.',
        );
        return;
      }
      late final List<WearableScanResult> results;
      try {
        results = await _gateway.scan(timeout: scanTimeout);
      } on WearableException catch (e) {
        _setNotice(_scanFailureNotice(e.code));
        return;
      }
      if (results.isEmpty) {
        _setNotice('No watch found nearby. Keep it close and try again.');
        return;
      }
      final candidate = WearableCompatibility.pickCandidate(results);
      if (candidate == null) {
        _setNotice(
          'Found Bluetooth devices nearby, but none looks like a '
          'supported watch. Only FitPro-compatible watches can connect.',
        );
        return;
      }
      late final bool connected;
      try {
        connected = await _connectWithRetry(candidate.deviceIdentifier);
      } on WearableException catch (e) {
        _setNotice(_connectFailureNotice(e.code));
        return;
      }
      if (!connected) {
        _setNotice('Could not connect to the watch. Make sure it is powered on and close by.');
        return;
      }
      final body = await _api.registerDevice(
        provider: 'FITPRO',
        deviceIdentifier: candidate.deviceIdentifier,
        // The scan name is the model ("Watch 8"). Inventing a manufacturer
        // from its first word produced "Watch Watch 8"; the real GATT
        // manufacturer string is not exposed by this protocol slice.
        manufacturer: null,
        model: candidate.name,
        capabilities: null,
      );
      final device = WearableDevice.fromJson(body);
      _device = device;
      await _cache.writeDevice(device);
      // Automatic fetch, part 1: the pairing just established the GATT
      // session, so the first snapshot is read and uploaded immediately
      // instead of waiting for a manual "Sync now" press. No reconnect is
      // attempted (the session exists), and the pairing stays in its
      // connecting state until the first batch is stored so the outcome
      // the user sees is "paired AND data flowing", not just "searched".
      // A failure surfaces an actionable notice; the watch remains paired.
      final fetched = await _runDeviceSync(
        attemptReconnect: false,
        userVisible: true,
      );
      if (fetched) {
        _setNotice('${device.displayName} connected.');
      } else if (_notice == null) {
        // A specific reason (band silent, permissions, rejected payload) is
        // more useful than a generic "first sync did not finish".
        _setNotice(
          '${device.displayName} paired, but the first sync did not finish. '
          'Use Sync now to try again.',
        );
      }
      await loadToday();
    } on Failure catch (e) {
      _setNotice(e.message);
    } on Object {
      _setNotice('Could not register the watch. Check your connection.');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Disconnects and forgets the registered watch (server + local cache).
  Future<void> forgetDevice() async {
    final device = _device;
    if (device == null) return;
    try {
      await _gateway.disconnect();
    } on Object {
      // Best-effort: the GATT session is torn down natively on next
      // connect/disconnect regardless; local state must clear anyway.
    }
    _device = null;
    await _cache.clearDevice();
    notifyListeners();
    try {
      await _api.deleteDevice(device.id);
    } on Object {
      // Best-effort: the local state is already cleared; a stale server
      // record is harmless and will be re-listed on next registration.
    }
  }

  // ── Live heart-rate monitoring ─────────────────────────────────────────

  /// Live samples from the band while a monitor session runs. Empty when no
  /// platform support exists — never seeded with synthetic readings.
  Stream<LiveHeartRateSample> get liveHeartRate => _gateway.liveHeartRate;

  /// Whether a monitor can be started: a paired device must exist and the
  /// platform side must be present. Connection itself is verified by the
  /// gateway call, not assumed here.
  bool get canMonitor => _device != null;

  /// Starts continuous heart-rate measurement. Returns null on success or an
  /// actionable message otherwise. Does not claim samples will arrive — only
  /// that the command sequence was delivered.
  Future<String?> startHeartRateMonitor() async {
    if (_device == null) return 'Connect your watch first.';
    try {
      if (await _gateway.startHeartRateMonitor()) {
        _monitorActive = true;
        return null;
      }
      return 'Could not start live measurement. Move the watch closer and '
          'try again.';
    } on WearableException catch (e) {
      return _connectFailureNotice(e.code);
    } on Object {
      return 'Live measurement is unavailable on this device.';
    }
  }

  /// Stops measurement. Returns true when an active session was stopped.
  Future<bool> stopHeartRateMonitor() async {
    try {
      return await _gateway.stopHeartRateMonitor();
    } on Object {
      return false;
    } finally {
      _monitorActive = false;
    }
  }

  /// Persists one live-monitoring session through the same durable
  /// enqueue → flush path a snapshot uses, so an offline session is queued
  /// rather than lost and duplicates are handled by the server's ingestion
  /// rules. Returns the number of readings accepted into the queue, or null
  /// when there is nothing to save.
  Future<int?> saveLiveHeartRate(List<LiveHeartRateSample> samples) async {
    final device = _device;
    if (device == null || samples.isEmpty) return null;
    final readings = <Map<String, dynamic>>[];
    for (final s in samples) {
      final timestamp = s.timestamp.toUtc().toIso8601String();
      readings.add({
        'metricType': 'HEART_RATE',
        'value': s.bpm.toDouble(),
        'unit': 'bpm',
        'timestamp': timestamp,
        'measurementType': 'DEVICE_MEASURED',
      });
      final spo2 = s.spo2;
      if (spo2 != null && spo2 >= 50 && spo2 <= 100) {
        readings.add({
          'metricType': 'SPO2',
          'value': spo2.toDouble(),
          'unit': '%',
          'timestamp': timestamp,
          'measurementType': 'DEVICE_MEASURED',
        });
      }
    }
    final batch = <String, dynamic>{
      'clientSyncId':
          'live-${DateTime.now().microsecondsSinceEpoch}-${readings.length}',
      'deviceId': device.id,
      'deviceStatus': {'connectionStatus': 'CONNECTED'},
      'readings': readings,
      'dailyActivity': <Map<String, dynamic>>[],
      'sleepSessions': <Map<String, dynamic>>[],
      'exerciseSessions': <Map<String, dynamic>>[],
    };
    await _cache.enqueueBatch(batch);
    _pendingBatches = (await _cache.readQueue()).length;
    notifyListeners();
    // The samples themselves prove the optical sensor works. Report that
    // observation so a stale capability list (e.g. a history snapshot that
    // returned no HR frames) cannot keep the dashboard saying "unsupported".
    // The server still decides verification; this is only SUPPORTED_UNVERIFIED.
    try {
      final capabilities = <Map<String, dynamic>>[
        {
          'metric': 'HEART_RATE',
          'supportStatus': 'SUPPORTED_UNVERIFIED',
          'retrievalMethod': 'VENDOR_PROTOCOL',
          'limitations': 'Live spot readings from the watch optical sensor; '
              'not continuous monitoring.',
        },
      ];
      if (samples.any((s) => s.spo2 != null)) {
        capabilities.add({
          'metric': 'SPO2',
          'supportStatus': 'SUPPORTED_UNVERIFIED',
          'retrievalMethod': 'VENDOR_PROTOCOL',
          'limitations': 'Blood-oxygen byte carried in the same optical '
              'heart-rate frame; measured on demand, not continuously.',
        });
      }
      await _api.reportCapabilities(device.id, capabilities);
    } on Object {
      // Non-fatal: the readings are already durable in the queue.
    }
    await flushQueue();
    await Future.wait([loadToday(), loadSummary()]);
    return readings.length;
  }

  // ── Sync ───────────────────────────────────────────────────────────────

  /// User-triggered sync ("Sync now"): reads the watch, enqueues the batch
  /// durably, then drains the queue, reporting every failure as an
  /// actionable notice.
  Future<void> syncNow() => _runDeviceSync(
        attemptReconnect: true,
        userVisible: true,
        forceReconnect: true,
      );

  /// Silent refresh used by the dashboard's screen-scoped timer. Steps are a
  /// cumulative device total, so re-reading every couple of minutes is what
  /// keeps "today" current while the screen is open — there is no background
  /// service and no polling after the screen closes. Skipped while another
  /// sync or a live heart-rate session owns the link, and never surfaces a
  /// banner: a sleeping band must not interrupt the dashboard.
  static const Duration minAutoSyncInterval = Duration(seconds: 90);

  Future<void> syncIfStale({Duration minInterval = minAutoSyncInterval}) async {
    if (_device == null || _syncing || _monitorActive || _connecting) return;
    final now = DateTime.now();
    final last = _lastSyncAt;
    if (last != null && now.difference(last) < minInterval) return;
    // Reuse a healthy link for the frequent ticks; reconnect from scratch
    // when it has been idle long enough that Android may hold a zombie GATT.
    final forceReconnect =
        last == null || now.difference(last) > const Duration(minutes: 10);
    await _runDeviceSync(
      attemptReconnect: true,
      userVisible: false,
      forceReconnect: forceReconnect,
    );
  }

  /// One watch read → durable enqueue → upload → dashboard refresh cycle.  ///
  /// Every connection entry point funnels through here so the sync contract
  /// (durable enqueue first, notices only when [userVisible]) cannot drift
  /// apart between the manual and the automatic paths. Automatic background
  /// calls use `userVisible: false` so a sleeping band or a missing
  /// permission never interrupts the dashboard with a warning banner.
  ///
  /// [successNotice] (only meaningful when [userVisible]) is published after
  /// a successful run, which lets a calling flow end "X connected." without
  /// racing the pipeline's own notice changes.
  Future<bool> _runDeviceSync({
    required bool attemptReconnect,
    required bool userVisible,
    String? successNotice,
    bool forceReconnect = false,
  }) async {
    final device = _device;
    if (device == null) {
      if (userVisible) _setNotice('Connect your watch first.');
      return false;
    }
    if (_syncing) return false;
    _syncing = true;
    if (userVisible) _notice = null;
    notifyListeners();
    try {
      if (attemptReconnect) {
        late final bool reconnected;
        try {
          reconnected = await _connectWithRetry(
            device.deviceIdentifier,
            forceReconnect: forceReconnect,
          );
        } on WearableException catch (e) {
          if (userVisible) _setNotice(_connectFailureNotice(e.code));
          return false;
        }
        if (!reconnected) {
          if (userVisible) {
            _setNotice(
              'Lost connection to the watch. Move it closer and try syncing again.',
            );
          }
          return false;
        }
      }
      late final WearableSnapshot? snapshot;
      try {
        snapshot = await _gateway.readSnapshot();
      } on WearableException catch (e) {
        if (userVisible) _setNotice(_snapshotFailureNotice(e.code));
        return false;
      }
      if (snapshot == null) {
        if (userVisible) _setNotice('Could not read data from the watch.');
        return false;
      }
      // A connected-but-silent band is not a successful data sync. Battery and
      // firmware may still have been read (real GATT reads), so capabilities
      // are reported, but no empty batch is enqueued — that is what produced
      // a queue full of battery-only payloads the server could never use.
      if (!snapshot.hasMetricData) {
        if (snapshot.capabilityReport.isNotEmpty) {
          try {
            await _api.reportCapabilities(device.id, snapshot.capabilityReport);
          } on Object {
            // Non-fatal: nothing to persist for this session.
          }
        }
        if (userVisible) {
          _setNotice(
            'The watch connected but reported no new health data. '
            'Keep it on your wrist and try again.',
          );
        }
        return false;
      }
      final batch = buildBatch(device, snapshot);
      await _cache.enqueueBatch(batch);
      _pendingBatches = (await _cache.readQueue()).length;
      notifyListeners();
      await flushQueue();
      // Capabilities are reported separately from the readings batch. This is
      // best-effort and carries observations only: the server decides what is
      // verified, so a failed report leaves the registry untouched rather than
      // silently claiming support.
      if (snapshot.capabilityReport.isNotEmpty) {
        try {
          await _api.reportCapabilities(device.id, snapshot.capabilityReport);
        } on Object {
          // Non-fatal: readings are already durable in the queue.
        }
      }
      await Future.wait([loadToday(), loadSummary()]);
      _lastSyncAt = DateTime.now();
      if (userVisible && successNotice != null) _setNotice(successNotice);
      return true;
    } on Object {
      if (userVisible) {
        _setNotice('Sync failed. Your data is saved and will retry later.');
      }
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Drains the durable queue, oldest first.
  ///
  /// Transient failures (network, 5xx, auth) stop the drain and keep the rest
  /// queued. A batch the server *permanently* rejects (400/404/409/422 — e.g.
  /// it references a device registration that no longer exists) is removed so
  /// one poisoned payload cannot block every later batch forever; the count is
  /// surfaced to the user instead of silently dropping data.
  Future<void> flushQueue() async {
    await _dropForeignBatches();
    final queue = await _cache.readQueue();
    _pendingBatches = queue.length;
    if (queue.isEmpty) return;
    notifyListeners();
    var discarded = 0;
    String? firstDiscardReason;
    for (final batch in queue) {
      final clientSyncId = batch['clientSyncId']?.toString();
      try {
        final body = await _api.syncPhysical(batch);
        final result = SyncResult.fromJson(body);
        if (clientSyncId != null) {
          await _cache.removeBatch(clientSyncId);
        }
        if (!result.isFullyAccepted) {
          final first = result.rejections.isNotEmpty
              ? result.rejections.first.reason
              : null;
          _setNotice(
            '${result.rejected} record${result.rejected == 1 ? '' : 's'} from a '
            'synced batch ${result.status == 'FAILED' ? 'were rejected' : 'were partly rejected'}.'
            '${first == null ? '' : ' Reason: $first'}',
          );
        }
      } on ServerFailure catch (e) {
        // Only definite client-side rejections are permanent. Everything else
        // (timeouts, 5xx, auth) keeps the queue intact for a later retry.
        if (!_isPermanentBatchError(e)) break;
        if (clientSyncId != null) await _cache.removeBatch(clientSyncId);
        discarded++;
        firstDiscardReason ??= e.message;
      } on Object {
        break;
      }
    }
    if (discarded > 0) {
      _setNotice(
        '$discarded unsynced batch${discarded == 1 ? '' : 'es'} could not be '
        'accepted by the server and were removed'
        '${firstDiscardReason == null ? '.' : ' ($firstDiscardReason).'}',
      );
    }
    _pendingBatches = (await _cache.readQueue()).length;
    if (!_disposed) notifyListeners();
  }

  /// A 4xx answer other than 401/403 means retrying the same payload can never
  /// succeed, so the batch is removed instead of blocking the queue.
  bool _isPermanentBatchError(ServerFailure failure) {
    switch (failure.code) {
      case 'HTTP_400':
      case 'HTTP_404':
      case 'HTTP_409':
      case 'HTTP_422':
        return true;
      default:
        return false;
    }
  }

  /// Drops queued batches that still reference a previous device registration
  /// (re-registering the watch creates a new server id). Such batches would
  /// always 404, and would block every newer batch behind them.
  Future<void> _dropForeignBatches() async {
    final device = _device;
    if (device == null) return;
    final queue = await _cache.readQueue();
    var dropped = 0;
    for (final batch in queue) {
      final batchDevice = batch['deviceId']?.toString();
      if (batchDevice == null || batchDevice == device.id) continue;
      final syncId = batch['clientSyncId']?.toString();
      if (syncId == null) continue;
      await _cache.removeBatch(syncId);
      dropped++;
    }
    if (dropped > 0) {
      _pendingBatches = (await _cache.readQueue()).length;
      _setNotice(
        '$dropped unsynced batch${dropped == 1 ? '' : 'es'} from an earlier '
        'watch registration could not be uploaded and were discarded. '
        'New readings sync normally.',
      );
    }
  }

  /// Turns one decoded watch snapshot into a `POST /physical/sync` body.
  @visibleForTesting
  Map<String, dynamic> buildBatch(WearableDevice device, WearableSnapshot s) {
    final readings = [
      for (final r in s.readings)
        {
          'metricType': r.metricType,
          'value': r.value,
          'unit': r.unit,
          'timestamp': r.timestamp.toUtc().toIso8601String(),
          'measurementType': r.measurementType,
        },
    ];
    final dailyActivity = <Map<String, dynamic>>[];
    // FitPro deletes history from the band after sending it once, so the
    // snapshot's per-day sums contain only the chunks fetched since the last
    // sync. Mark them as deltas so the backend adds them to the stored day
    // instead of replacing it (which dropped earlier steps).
    for (final row in s.dailyActivities) {
      dailyActivity.add({...row, 'aggregation': 'INTERVAL_DELTA'});
    }
    if (dailyActivity.isEmpty && s.dailyActivity != null) {
      dailyActivity.add({...s.dailyActivity!, 'aggregation': 'INTERVAL_DELTA'});
    }
    final deviceStatus = <String, dynamic>{
      'connectionStatus': 'CONNECTED',
      if (s.batteryLevel != null) 'batteryLevel': s.batteryLevel,
      if (s.charging != null) 'charging': s.charging,
      if (s.firmwareVersion != null) 'firmwareVersion': s.firmwareVersion,
    };
    return {
      'clientSyncId':
          'c-${DateTime.now().microsecondsSinceEpoch}-${readings.length}',
      'deviceId': device.id,
      'deviceStatus': deviceStatus,
      'readings': readings,
      'dailyActivity': dailyActivity,
      'sleepSessions': s.sleepSessions,
      'exerciseSessions': s.exerciseSessions,
    };
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// Bounded reconnect: a `false` return or a transient `BUSY` is retried at
  /// most [_maxConnectAttempts] times with a short backoff, then reported as
  /// a plain failure. Non-retryable errors (Bluetooth off, permission, bad
  /// address) rethrow immediately — retrying those would just burn battery.
  /// Total worst-case added latency is ~1.2 s; there is deliberately no
  /// infinite loop and no background polling.
  static const int _maxConnectAttempts = 3;
  static const List<Duration> _connectBackoff = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];

  Future<bool> _connectWithRetry(
    String deviceIdentifier, {
    bool forceReconnect = false,
  }) async {
    // A band that slept or drifted out of range leaves Android holding a
    // GATT object in a zombie state: `connect()` sees it as already
    // connected and returns immediately, then the fetch writes into a dead
    // link and hangs until the watchdog. Dropping the stale handle first is
    // what turns "Sync now" into a real reconnect.
    if (forceReconnect) {
      try {
        await _gateway.disconnect();
      } on Object {
        // Nothing was connected; proceed with a fresh connect.
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    for (var attempt = 0; ; attempt++) {
      try {
        if (await _gateway.connect(deviceIdentifier)) return true;
      } on WearableException catch (e) {
        if (e.code != 'BUSY' || attempt + 1 >= _maxConnectAttempts) rethrow;
      }
      if (attempt + 1 >= _maxConnectAttempts) return false;
      await Future.delayed(_connectBackoff[attempt]);
    }
  }

  /// Actionable copy per native scan failure code.
  String _scanFailureNotice(String code) => switch (code) {
        'BLUETOOTH_OFF' =>
          'Bluetooth is turned off. Turn it on to find your watch.',
        'PERMISSION_REQUIRED' =>
          'Bluetooth permission is required to find your watch. '
              'Allow nearby-device access in Settings, then try again.',
        'BUSY' => 'A scan is already running. Wait a moment and try again.',
        _ => 'Scan failed. Move the watch closer and try again.',
      };

  /// Actionable copy per native connect failure code.
  String _connectFailureNotice(String code) => switch (code) {
        'BLUETOOTH_OFF' =>
          'Bluetooth is turned off. Turn it on before connecting.',
        'PERMISSION_REQUIRED' =>
          'Bluetooth permission is required to connect to your watch.',
        'BUSY' => 'A connection is already in progress. Try again shortly.',
        'BAD_ARGUMENT' =>
          'The saved watch address looks invalid. Forget the watch and pair it again.',
        _ =>
          'Could not connect to the watch. Make sure it is powered on and close by.',
      };

  /// Actionable copy per native snapshot failure code.
  String _snapshotFailureNotice(String code) => switch (code) {
        'NOT_CONNECTED' =>
          'Lost connection to the watch. Move it closer and try syncing again.',
        'BUSY' => 'A sync is already running. Wait for it to finish.',
        _ => 'Could not read data from the watch.',
      };

  void _start() {
    _loading = true;
    _error = null;
    _deferNotify();
  }

  /// Listeners must not be notified synchronously from a loader a screen
  /// calls out of `initState`: the provider scope sits above the router, and
  /// marking it while the framework is still building that screen trips its
  /// "setState() or markNeedsBuild() called during build" assertion. State is
  /// already assigned synchronously, so the in-flight build reads the right
  /// values; this only schedules the follow-up rebuild safely.
  void _deferNotify() {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  void _fail(Object e) {
    _error = e is Failure
        ? e.message
        : 'Could not load your physical wellness data.';
    _loading = false;
    notifyListeners();
  }

  void _setNotice(String message) {
    _notice = message;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
