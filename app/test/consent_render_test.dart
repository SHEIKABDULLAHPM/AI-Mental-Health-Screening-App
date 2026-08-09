import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/onboarding/consent/privacy_consent_screen.dart';
import 'package:mindease/features/onboarding/permissions/permissions_screen.dart';

Widget harness() {
  final router = GoRouter(
    initialLocation: '/consent',
    routes: [
      GoRoute(
        path: '/consent',
        builder: (context, state) => const PrivacyConsentScreen(),
      ),
      GoRoute(
        path: '/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(path: '/register', builder: (context, state) => const Scaffold()),
      GoRoute(path: '/screening', builder: (context, state) => const Scaffold()),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}

void main() {
  testWidgets('consent screen paints content at phone size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    await tester.pumpWidget(harness());
    // Give the router a moment to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final titleFinder = find.text('Before we begin');
    final btnFinder = find.text('Accept & Continue');
    final checkboxFinder = find.text('I accept the Privacy Policy');

    expect(titleFinder.evaluate(), isNotEmpty, reason: 'title should exist');
    expect(btnFinder.evaluate(), isNotEmpty, reason: 'button should exist');

    for (final f in [titleFinder, btnFinder, checkboxFinder]) {
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f.first);
      debugPrint('GEOM consent "${f.first.evaluate().first.widget}" rect=$rect');
    }
    await tester.binding.setSurfaceSize(null);
  });
}