import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Resolves the backend base URL at runtime.
///
/// [AppConfig.apiBaseUrl] is compiled in and defaults to the emulator-only
/// alias `10.0.2.2`; a physical phone cannot route to that address, so every
/// request fails with "Unable to reach the server". A value saved here
/// overrides the build default for every later request, which lets a device be
/// pointed at the host actually running the backend without a rebuild.
class ServerEndpoint {
  ServerEndpoint._();

  static const String _prefsKey = 'server.api_base_url';

  static String? _override;

  /// Hostnames, IPv4 and bracketed IPv6 only. `Uri` happily percent-encodes
  /// spaces in a host, which would produce an address that can never resolve.
  static final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9._:\-\[\]]+$');

  /// Base URL every request is built from.
  static String get current => _override ?? AppConfig.apiBaseUrl;

  /// The address compiled into this build (`--dart-define=API_BASE_URL`).
  static String get buildDefault => AppConfig.apiBaseUrl;

  /// True when the build-time address has been replaced by a saved one.
  static bool get isOverridden => _override != null;

  /// Performs the reachability probe. Replaced in tests.
  static Future<bool> Function() prober = probeDefault;

  /// Loads a previously saved override. Call once during startup, before the
  /// first request is issued.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _override = normalize(prefs.getString(_prefsKey));
  }

  /// Persists [raw] as the API base URL and returns the normalised value.
  /// Returns `null` — and saves nothing — when [raw] is not a usable address.
  static Future<String?> save(String raw) async {
    final value = normalize(raw);
    if (value == null) return null;
    _override = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    return value;
  }

  /// Forgets the override so the build-time address is used again.
  static Future<void> reset() async {
    _override = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Turns user input into a usable base URL, or `null` when it cannot be one.
  ///
  /// Accepts a bare `host`, `host:port`, or a full
  /// `http(s)://host[:port][/path]`. A missing scheme becomes `http://` and an
  /// empty path becomes `/api/v1`, so "192.168.1.4:8080" is enough to point a
  /// physical phone at a dev host.
  static String? normalize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'http://$trimmed',
    );
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    if (!_hostPattern.hasMatch(uri.host)) return null;

    // A base URL may not carry a query or fragment: every request appends its
    // own path to it. The URI is rebuilt from its parts because `replace`
    // keeps null values, which would leave an empty query behind.
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path.isEmpty ? '/api/v1' : path,
    ).toString();
  }

  /// Root-level actuator health URL for the configured server.
  static Uri healthUri() {
    final base = Uri.parse(current);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/actuator/health',
    );
  }

  /// Asks the configured server whether it is up.
  static Future<bool> probe() async {
    try {
      return await prober();
    } catch (_) {
      return false;
    }
  }

  /// Real probe: a short, unauthenticated GET against the backend's health
  /// endpoint. Uses a bare client so the app's auth interceptor and its
  /// token-refresh retry never run against the health URL.
  static Future<bool> probeDefault() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    final response = await dio.get<dynamic>(healthUri().toString());
    if (response.statusCode != 200) return false;
    final body = response.data;
    return body is Map && body['status'] == 'UP';
  }
}
