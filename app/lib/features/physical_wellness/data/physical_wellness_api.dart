/// Physical Wellness endpoints on the backend (`/wearables` + `/physical/*`).
///
/// Implemented by [FeatureApi] in production; stubbed in tests. Every method
/// returns the unwrapped inner `data` of the `{success, data}` envelope as a
/// raw map — controllers own the mapping into domain models.
abstract class PhysicalWellnessApi {
  /// Registers the connected watch (`POST /wearables`, 201 on create).
  Future<Map<String, dynamic>> registerDevice({
    required String provider,
    required String deviceIdentifier,
    String? manufacturer,
    String? model,
    String? firmwareVersion,
    List<String>? capabilities,
    int? batteryLevel,
  });

  /// Lists all wearables registered by the current user (`GET /wearables`).
  Future<List<Map<String, dynamic>>> listDevices();

  /// Patches battery/connection status (`PUT /wearables/{id}/status`).
  Future<Map<String, dynamic>> updateDeviceStatus(
    String deviceId, {
    int? batteryLevel,
    bool? charging,
    String? connectionStatus,
    String? firmwareVersion,
  });

  /// Forgets a device (`DELETE /wearables/{id}`).
  Future<void> deleteDevice(String deviceId);

  /// The dashboard payload for "today" (`GET /physical/today`).
  Future<Map<String, dynamic>> getPhysicalToday();

  /// Daily activity history (`GET /physical/activity?days=`).
  Future<Map<String, dynamic>> getPhysicalActivity({int? days});

  /// Heart-rate history (`GET /physical/heart-rate?hours=`).
  Future<Map<String, dynamic>> getPhysicalHeartRate({int? hours});

  /// Sleep history (`GET /physical/sleep?limit=`).
  Future<Map<String, dynamic>> getPhysicalSleep({int? limit});

  /// Exercise history (`GET /physical/exercise?limit=`).
  Future<Map<String, dynamic>> getPhysicalExercise({int? limit});

  /// Weekly trend (`GET /physical/summary`).
  Future<Map<String, dynamic>> getPhysicalSummary();

  /// Uploads one ingestion batch (`POST /physical/sync`).
  Future<Map<String, dynamic>> syncPhysical(Map<String, dynamic> payload);

  // ── Hydration (`/physical/hydration`) ──────────────────────────────────

  Future<Map<String, dynamic>> getHydration({int? days});

  /// Logs an entry. [timestamp] doubles as the replay key: the server stores
  /// it verbatim, so a retried batch can be detected instead of duplicating.
  Future<Map<String, dynamic>> addHydration({
    required double amount,
    String? unit,
    DateTime? timestamp,
  });

  Future<Map<String, dynamic>> updateHydration(
    String entryId, {
    required double amount,
    String? unit,
    DateTime? timestamp,
  });

  Future<void> deleteHydration(String entryId);

  Future<Map<String, dynamic>> updateHydrationTarget(int targetMl);

  // ── Body measurements (`/physical/body`) ───────────────────────────────

  Future<Map<String, dynamic>> getBody({int? limit});

  Future<Map<String, dynamic>> addBodyMeasurement({
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  });

  Future<Map<String, dynamic>> updateBodyMeasurement(
    String measurementId, {
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  });

  Future<void> deleteBodyMeasurement(String measurementId);

  // ── Goals, trends, insights ────────────────────────────────────────────

  Future<Map<String, dynamic>> getGoals();

  /// Full replacement: an omitted field clears that target (never inherits a
  /// stale value the user did not confirm).
  Future<Map<String, dynamic>> updateGoals(Map<String, dynamic> targets);

  /// Applies AI-suggested targets. The backend ignores invalid or user-owned
  /// metrics and returns what was applied and skipped.
  Future<Map<String, dynamic>> applyAiGoalRecommendations(
      List<Map<String, dynamic>> recommendations);

  Future<Map<String, dynamic>> getTrends({int? days});

  Future<Map<String, dynamic>> getInsights();

  // ── Capability registry (`/wearables/{id}/capabilities`) ───────────────

  Future<Map<String, dynamic>> getCapabilities(String deviceId);

  /// Reports observed capabilities. The server downgrades any verification
  /// claim, so clients must only send `SUPPORTED_UNVERIFIED`/absent rows.
  Future<Map<String, dynamic>> reportCapabilities(
    String deviceId,
    List<Map<String, dynamic>> capabilities,
  );
}
