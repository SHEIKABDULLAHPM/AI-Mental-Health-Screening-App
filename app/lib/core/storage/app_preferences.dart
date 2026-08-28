import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for onboarding & lightweight session state.
class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPreferences> load() async {
    return AppPreferences(await SharedPreferences.getInstance());
  }

  static const String _kOnboarded = 'onboarding.completed';
  static const String _kConsented = 'onboarding.consented';
  static const String _kPermissionsGranted = 'onboarding.permissions_granted';
  static const String _kSessionActive = 'session.active';
  static const String _kUsername = 'session.name';
  static const String _kRememberMe = 'session.remember_me';

  bool get isOnboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool value) => _prefs.setBool(_kOnboarded, value);

  bool get hasConsented => _prefs.getBool(_kConsented) ?? false;
  Future<void> setConsent(bool value) => _prefs.setBool(_kConsented, value);

  bool get permissionsGranted => _prefs.getBool(_kPermissionsGranted) ?? false;
  Future<void> setPermissionsGranted(bool value) =>
      _prefs.setBool(_kPermissionsGranted, value);

  bool get isSessionActive => _prefs.getBool(_kSessionActive) ?? false;
  Future<void> setSessionActive(bool value) =>
      _prefs.setBool(_kSessionActive, value);

  String get username => _prefs.getString(_kUsername) ?? '';
  Future<void> setUsername(String value) => _prefs.setString(_kUsername, value);

  bool get rememberMe => _prefs.getBool(_kRememberMe) ?? false;
  Future<void> setRememberMe(bool value) => _prefs.setBool(_kRememberMe, value);

  Future<void> saveSession(
      {required String username, bool remember = true,}) async {
    await setUsername(username);
    await setRememberMe(remember);
    await setSessionActive(true);
  }

  Future<void> resetOnboarding() async {
    await setOnboarded(false);
    await setConsent(false);
    await setPermissionsGranted(false);
  }

  /// Marks the session as ended and forgets the cached account name.
  Future<void> clearSession() async {
    await setSessionActive(false);
    await setUsername('');
    await setRememberMe(false);
  }
}
