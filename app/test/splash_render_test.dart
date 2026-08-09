import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/onboarding/splash/splash_screen.dart';
import 'package:mindease/shared/widgets/app_logo.dart';

void main() {
  late GoRouter router;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
        GoRoute(path: '/welcome', builder: (c, s) => const Scaffold()),
        GoRoute(path: '/dashboard', builder: (c, s) => const Scaffold()),
      ],
    );
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 2.8125;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  void expectAllTextVisible(WidgetTester tester, double viewportH) {
    for (final needle in [
      'MindEase',
      'Breathe. Understand. Thrive.',
      'Preparing your experience…',
      'Version 1.0.0',
    ]) {
      final f = find.text(needle);
      expect(f.evaluate(), isNotEmpty, reason: 'text "$needle" exists');
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(0), reason: '"$needle" top on screen');
      expect(
        r.bottom,
        lessThanOrEqualTo(viewportH),
        reason: '"$needle" bottom on screen',
      );
    }
  }

  testWidgets('splash centered & fully visible on tall phone', (tester) async {
    await pumpAt(tester, const Size(1080, 2400));
    const viewportH = 2400 / 2.8125;
    const viewportW = 1080 / 2.8125;

    final logo = tester.getRect(find.byType(AppLogo));
    debugPrint('GEOM splash AppLogo $logo');
    expect(
      logo.center.dx,
      closeTo(viewportW / 2, 1.0),
      reason: 'brand horizontally centered',
    );
    expect(
      logo.center.dy,
      closeTo(viewportH / 2, 120.0),
      reason: 'brand vertically centered-ish',
    );
    expectAllTextVisible(tester, viewportH);
    await tester.pump(const Duration(milliseconds: 2000));
  });

  testWidgets('splash fully visible on short screen', (tester) async {
    await pumpAt(
      tester,
      const Size(1080, 1400), // ~100 logical px taller than content
    );
    const viewportH = 1400 / 2.8125;
    expectAllTextVisible(tester, viewportH);
    await tester.pump(const Duration(milliseconds: 2000));
  });
}
