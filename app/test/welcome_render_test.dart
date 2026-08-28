import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/onboarding/welcome/welcome_screen.dart';
import 'package:mindease/shared/widgets/app_logo.dart';

void main() {
  testWidgets('welcome layout extents at phone size', (tester) async {
    tester.view.devicePixelRatio = 2.8125;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pump();

    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
        GoRoute(path: '/register', builder: (c, s) => const Scaffold()),
        GoRoute(path: '/login', builder: (c, s) => const Scaffold()),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    const viewportH = 2400 / 2.8125;
    debugPrint('GEOM logical screen 384x$viewportH');
    for (final needle in [
      'Your companion for understanding, nurturing and growing your mental wellbeing — one small step at a time.',
      'AI Mental Health Screening',
      'Personalized Wellness Guidance',
      'Daily Wellness Monitoring',
      'Secure & Private',
      'Get Started',
      'Sign In',
    ]) {
      final f = find.text(needle);
      if (f.evaluate().isNotEmpty) {
        final r = tester.getRect(f);
        debugPrint('GEOM welcome "$needle" rect=$r visible=${r.bottom < viewportH}');
      }
    }
    debugPrint('GEOM logo ${tester.getRect(find.byType(AppLogoMark))}');
    for (final needle in ['Terms & Conditions', 'Privacy Policy']) {
      final f = find.text(needle);
      if (f.evaluate().isNotEmpty) {
        final r = tester.getRect(f);
        debugPrint('GEOM welcome "$needle" rect=$r');
      }
    }
    // Report the scrollable's dimension.
    final scroll = find.byType(SingleChildScrollView);
    if (scroll.evaluate().isNotEmpty) {
      final r = tester.getRect(scroll);
      debugPrint('GEOM scrollview rect=$r');
    }
  });
}