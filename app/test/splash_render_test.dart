import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/onboarding/splash/splash_screen.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';
import 'package:mindease/shared/widgets/app_logo.dart';

void main() {
  group('SplashScreen', () {
    const needles = ['Preparing your experience…', 'Version 1.0.0'];

    late GoRouter router;

    setUp(() {
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
      // Entrance animation runs for 720ms; advance past it with fixed pumps
      // instead of pumpAndSettle (the loading dots repeat indefinitely).
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('renders brand lockup and meta block on tall screens',
        (tester) async {
      await pumpAt(tester, const Size(1080, 2280));

      expect(find.byType(AppBackdrop), findsOneWidget);
      expect(find.byType(AppLogo), findsOneWidget);

      final logo = tester.getRect(find.byType(AppLogo));
      final screenCenter = tester.getRect(find.byType(Scaffold)).center;
      expect(
        (logo.center - screenCenter).distance,
        lessThan(40),
        reason: 'brand mark should sit near the screen center',
      );

      for (final needle in needles) {
        expect(find.text(needle), findsOneWidget);
      }

      // Let the navigation delay elapse and leave the splash so the
      // repeating loading-dots animation can be disposed.
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 400));
      // Elapse the 45 s splash navigation bound (SplashScreen caps the
      // session check so it can never strand the user): the timeout fires,
      // the app navigates to /welcome, and no timer is left pending.
      await tester.pump(const Duration(seconds: 46));
      await tester.pump(const Duration(milliseconds: 400));
      // Allow the /welcome transition to settle before asserting.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('renders brand lockup and meta block on short screens',
        (tester) async {
      await pumpAt(tester, const Size(1080, 1400));

      expect(find.byType(AppLogo), findsOneWidget);

      for (final needle in needles) {
        expect(find.text(needle), findsOneWidget);
      }

      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 46));
      await tester.pump(const Duration(milliseconds: 400));
      // Allow the /welcome transition to settle before asserting.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(SplashScreen), findsNothing);
    });
  });
}
