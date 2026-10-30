import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mindease/core/config/app_config.dart';
import 'package:mindease/core/config/server_endpoint.dart';

/// The app ships pointing at the emulator-only alias `10.0.2.2`, which a
/// physical phone cannot route to ("Unable to reach the server"). These tests
/// pin the runtime override that lets a device be pointed at a reachable host.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerEndpoint.prober = () async => true;
  });

  tearDown(() async {
    await ServerEndpoint.reset();
    ServerEndpoint.prober = ServerEndpoint.probeDefault;
  });

  group('normalize', () {
    test('accepts a bare host and adds scheme and api path', () {
      expect(ServerEndpoint.normalize('192.168.1.4'), 'http://192.168.1.4/api/v1');
    });

    test('accepts host:port', () {
      expect(
        ServerEndpoint.normalize('192.168.1.4:8080'),
        'http://192.168.1.4:8080/api/v1',
      );
    });

    test('keeps an explicit scheme and path', () {
      expect(
        ServerEndpoint.normalize('https://api.example.com/api/v1'),
        'https://api.example.com/api/v1',
      );
    });

    test('strips trailing slashes and query', () {
      expect(
        ServerEndpoint.normalize('http://10.0.0.5:8080/api/v1/?debug=1'),
        'http://10.0.0.5:8080/api/v1',
      );
    });

    test('rejects empty, hostless and non-http input', () {
      expect(ServerEndpoint.normalize(''), isNull);
      expect(ServerEndpoint.normalize('   '), isNull);
      expect(ServerEndpoint.normalize('http://'), isNull);
      expect(ServerEndpoint.normalize('ftp://192.168.1.4'), isNull);
      expect(ServerEndpoint.normalize(null), isNull);
    });
  });

  group('override lifecycle', () {
    test('current falls back to the build default', () async {
      await ServerEndpoint.load();
      expect(ServerEndpoint.current, AppConfig.apiBaseUrl);
      expect(ServerEndpoint.isOverridden, isFalse);
    });

    test('save persists an override that load restores', () async {
      final saved = await ServerEndpoint.save('192.168.1.4:8080');
      expect(saved, 'http://192.168.1.4:8080/api/v1');
      expect(ServerEndpoint.current, saved);
      expect(ServerEndpoint.isOverridden, isTrue);

      // Simulate a fresh start against the same preferences.
      ServerEndpoint.prober = () async => true;
      await ServerEndpoint.load();
      expect(ServerEndpoint.current, 'http://192.168.1.4:8080/api/v1');
    });

    test('save refuses an unusable address and keeps the previous value',
        () async {
      await ServerEndpoint.save('192.168.1.4:8080');
      final rejected = await ServerEndpoint.save('not a url');
      expect(rejected, isNull);
      expect(ServerEndpoint.current, 'http://192.168.1.4:8080/api/v1');
    });

    test('reset returns to the build default and clears storage', () async {
      await ServerEndpoint.save('192.168.1.4:8080');
      await ServerEndpoint.reset();
      expect(ServerEndpoint.isOverridden, isFalse);
      expect(ServerEndpoint.current, AppConfig.apiBaseUrl);

      await ServerEndpoint.load();
      expect(ServerEndpoint.current, AppConfig.apiBaseUrl);
    });

    test('a corrupt stored value is ignored rather than used', () async {
      SharedPreferences.setMockInitialValues(
        {'server.api_base_url': 'http://'},
      );
      await ServerEndpoint.load();
      expect(ServerEndpoint.isOverridden, isFalse);
      expect(ServerEndpoint.current, AppConfig.apiBaseUrl);
    });
  });

  group('health uri', () {
    test('is rooted at the configured origin, not the api path', () async {
      await ServerEndpoint.save('192.168.1.4:8080');
      expect(
        ServerEndpoint.healthUri().toString(),
        'http://192.168.1.4:8080/actuator/health',
      );
    });
  });

  group('probe', () {
    test('reports an unreachable server instead of throwing', () async {
      ServerEndpoint.prober = () async => throw StateError('socket refused');
      expect(await ServerEndpoint.probe(), isFalse);
    });
  });
}
