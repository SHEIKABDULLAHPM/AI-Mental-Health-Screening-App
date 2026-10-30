import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/api/mindease_api.dart';
import 'package:mindease/core/auth/session_store.dart';
import 'package:mindease/core/media/media_upload_service.dart';
import 'package:mindease/core/network/dio_client.dart';
import 'package:mindease/core/router/app_router.dart';
import 'package:mindease/core/storage/app_preferences.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';
import 'package:mindease/features/physical_wellness/data/physical_local_cache.dart';
import 'package:mindease/features/physical_wellness/data/wearable_gateway.dart';
import 'package:mindease/features/wellness_analysis/data/wellness_analysis_api.dart';

/// Lightweight app-wide services shared by the onboarding and dashboard flows.
final SessionStore sessionStore = SessionStore();
final DioClient dioClient = DioClient();
final MindeaseApi mindeaseApi = MindeaseApi(dioClient);
final FeatureApi featureApi = FeatureApi(dioClient);
final MediaUploadService mediaUploadService = MediaUploadService(dioClient.dio);

/// Physical Wellness: bridges to the native BLE layer (MethodChannel) and
/// the SharedPreferences JSON cache backing offline reads + the sync queue.
final WearableGateway wearableGateway = MethodChannelWearableGateway();
final PhysicalLocalCache physicalLocalCache = PhysicalJsonCache();

/// Wires up the DioClient session-expiry callback so that an expired or
/// invalid refresh token immediately clears local state and forces the
/// user back to the welcome/login screen via the router.
void _setupSessionExpiry() {
  dioClient.onSessionExpired = () async {
    await sessionStore.clear();
    final prefs = await AppPreferences.load();
    await prefs.clearSession();
    ScreeningSession.reset();
    // Navigate to welcome using the GoRouter instance (safe from any context).
    _navigateToWelcome();
  };
}

void _navigateToWelcome() {
  try {
    AppRouter.router.go('/welcome');
  } catch (_) {
    // Router may not be initialized yet during startup.
  }
}

/// Call once during app startup (e.g. in main()) to activate the listener.
void initServices() {
  _setupSessionExpiry();
}

/// Signs the user out on the server (best-effort) and wipes every local trace
/// of the session. Safe to call even when the session is already invalid or
/// the backend is unreachable — local sign-out always proceeds.
Future<void> logout() async {
  final refreshToken = await sessionStore.refreshToken();
  if (refreshToken != null) {
    try {
      await mindeaseApi.logout(refreshToken);
    } on Object {
      // Offline or expired session: local sign-out must still complete.
    }
  }
  await sessionStore.clear();
  final prefs = await AppPreferences.load();
  await prefs.clearSession();
  // Never let a previous user's draft leak into the next sign-in.
  ScreeningSession.reset();
}

late final WellnessAnalysisApi wellnessAnalysisApi =
    WellnessAnalysisApi(dioClient);
