import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({SharedPreferences? prefs}) : _prefs = prefs;

  static const String _kUsers = 'mindease_users';
  static const String _kSession = 'mindease_session';
  static const String _kOnboarded = 'mindease_onboarding_complete';
  static const String _kRemember = 'mindease_remember_me';
  static const String _kOtp = 'mindease_reset_otp';
  static const String _kOtpEmail = 'mindease_reset_otp_email';
  static const String _kWellness = 'mindease_wellness';

  static const String demoEmail = 'demo@mindease.app';
  static const String demoPassword = 'Demo@1234';

  final SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<void> signUp({
    required UserProfile profile,
    required String password,
  }) async {
    final prefs = await _instance;
    final users = _readUsers(prefs);
    final key = profile.email.toLowerCase();
    if (users.containsKey(key)) {
      throw AuthException(
        'An account with this email already exists. Try signing in instead.',
      );
    }
    users[key] = jsonEncode({
      'password': password,
      'profile': profile.toJson(),
    });
    await prefs.setString(_kUsers, jsonEncode(users));
    await _startSession(prefs, profile);
  }

  Future<bool> login({required String email, required String password}) async {
    final prefs = await _instance;
    final key = email.toLowerCase();
    var users = _readUsers(prefs);

    if (!users.containsKey(key) &&
        key == demoEmail &&
        password == demoPassword) {
      const demo = UserProfile(
        fullName: 'Demo User',
        email: demoEmail,
        gender: 'Prefer not to say',
      );
      users[key] = jsonEncode({
        'password': demoPassword,
        'profile': demo.toJson(),
      });
      await prefs.setString(_kUsers, jsonEncode(users));
    }

    final entry = users[key];
    if (entry == null) return false;
    final data = jsonDecode(entry) as Map<String, dynamic>;
    if (data['password'] != password) return false;
    await _startSession(
      prefs,
      UserProfile.fromJson(data['profile'] as Map<String, dynamic>),
    );
    return true;
  }

  Future<void> _startSession(
    SharedPreferences prefs,
    UserProfile profile,
  ) async {
    await prefs.setString(_kSession, jsonEncode(profile.toJson()));
  }

  Future<UserProfile?> currentUser() async {
    final prefs = await _instance;
    final raw = prefs.getString(_kSession);
    if (raw == null) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<bool> isLoggedIn() async => (await currentUser()) != null;

  Future<void> logout() async {
    final prefs = await _instance;
    await prefs.remove(_kSession);
  }

  Future<void> completeOnboarding() async {
    final prefs = await _instance;
    await prefs.setBool(_kOnboarded, true);
  }

  Future<bool> isOnboarded() async {
    final prefs = await _instance;
    return prefs.getBool(_kOnboarded) ?? false;
  }

  Future<void> setRememberMe(bool value) async {
    final prefs = await _instance;
    await prefs.setBool(_kRemember, value);
  }

  Future<bool> getRememberMe() async {
    final prefs = await _instance;
    return prefs.getBool(_kRemember) ?? false;
  }

  Future<void> saveWellness({required int score, required String focus}) async {
    final prefs = await _instance;
    await prefs.setString(
      _kWellness,
      jsonEncode({'score': score, 'focus': focus}),
    );
  }

  Future<Map<String, dynamic>?> loadWellness() async {
    final prefs = await _instance;
    final raw = prefs.getString(_kWellness);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<String> sendResetOtp(String email) async {
    final prefs = await _instance;
    final otp = (Random().nextInt(900000) + 100000).toString();
    await prefs.setString(_kOtp, otp);
    await prefs.setString(_kOtpEmail, email.toLowerCase());
    return otp;
  }

  Future<bool> verifyOtp(String email, String otp) async {
    final prefs = await _instance;
    final stored = prefs.getString(_kOtp);
    final storedEmail = prefs.getString(_kOtpEmail);
    return storedEmail == email.toLowerCase() && stored == otp;
  }

  Future<bool> updatePassword({
    required String email,
    required String newPassword,
  }) async {
    final prefs = await _instance;
    final users = _readUsers(prefs);
    final key = email.toLowerCase();
    final entry = users[key];
    if (entry == null) return false;
    final data = jsonDecode(entry) as Map<String, dynamic>;
    data['password'] = newPassword;
    users[key] = jsonEncode(data);
    await prefs.setString(_kUsers, jsonEncode(users));
    await prefs.remove(_kOtp);
    await prefs.remove(_kOtpEmail);
    return true;
  }

  Map<String, String> _readUsers(SharedPreferences prefs) {
    final raw = prefs.getString(_kUsers);
    if (raw == null) return <String, String>{};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }
}
