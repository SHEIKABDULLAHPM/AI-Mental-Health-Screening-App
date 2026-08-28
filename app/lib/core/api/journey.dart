import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/storage/app_preferences.dart';

/// Helper that maps a fresh/returning user's journey progress onto the next
/// route the app must render. DF: any incomplete consent leads /consent, the
/// local permissions step is skipped when already granted, and a completed
/// assessment always lands on the dashboard.
class JourneyRouter {
  JourneyRouter._();

  static const String dashboard = '/dashboard';
  static const String consent = '/consent';
  static const String permissions = '/permissions';
  static const String screening = '/screening';
  static const String welcome = '/welcome';

  static Future<String> nextRoute(MindeaseUser user) async {
    if (user.screeningStatus == 'COMPLETED') return dashboard;

    if (user.consentStatus != 'COMPLETED') return consent;

    final prefs = await AppPreferences.load();
    return prefs.permissionsGranted ? screening : permissions;
  }
}
