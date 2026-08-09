import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mindease/features/onboarding/auth/forgot_password/forgot_password_email_screen.dart';
import 'package:mindease/features/onboarding/auth/forgot_password/otp_verification_screen.dart';
import 'package:mindease/features/onboarding/auth/forgot_password/reset_password_screen.dart';
import 'package:mindease/features/onboarding/auth/forgot_password/reset_success_screen.dart';
import 'package:mindease/features/onboarding/auth/login/login_screen.dart';
import 'package:mindease/features/onboarding/auth/register/register_screen.dart';
import 'package:mindease/features/onboarding/consent/privacy_consent_screen.dart';
import 'package:mindease/features/onboarding/permissions/permissions_screen.dart';
import 'package:mindease/features/onboarding/screening/ai_processing_screen.dart';
import 'package:mindease/features/onboarding/screening/screening_screen.dart';
import 'package:mindease/features/onboarding/screening/screening_session.dart';
import 'package:mindease/features/onboarding/screening/wellness_profile_screen.dart';
import 'package:mindease/features/onboarding/splash/splash_screen.dart';
import 'package:mindease/features/onboarding/welcome/welcome_screen.dart';

Widget harness(String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (c, s) => const ForgotPasswordEmailScreen(),
      ),
      GoRoute(
        path: '/forgot-password/otp',
        builder: (c, s) => const OtpVerificationScreen(),
      ),
      GoRoute(
        path: '/forgot-password/reset',
        builder: (c, s) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/forgot-password/success',
        builder: (c, s) => const ResetSuccessScreen(),
      ),
      GoRoute(path: '/consent', builder: (c, s) => const PrivacyConsentScreen()),
      GoRoute(path: '/permissions', builder: (c, s) => const PermissionsScreen()),
      GoRoute(path: '/screening', builder: (c, s) => const ScreeningScreen()),
      GoRoute(path: '/processing', builder: (c, s) => const AiProcessingScreen()),
      GoRoute(
        path: '/wellness-profile',
        builder: (c, s) => const WellnessProfileScreen(),
      ),
      GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
    ],
  );
  return MaterialApp.router(theme: AppTheme.light(), routerConfig: router);
}

/// Captures Flutter error diagnostics (with offending widget) instead of letting
/// the default handler swallow them.
final List<String> _capturedErrors = [];

void _installErrorCapture() {
  _capturedErrors.clear();
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    _capturedErrors.add(details.toString());
    original?.call(details);
  };
}

String _errorHead() {
  final b = StringBuffer();
  for (final e in _capturedErrors) {
    final clipped = e.split('\n').take(30).join('\n');
    b.write('\n---CLIP---\n$clipped');
  }
  return b.toString().trim();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreeningSession.reset();
    ScreeningSession.firstName = null;
  });

  testWidgets('audit: all onboarding+auth screens paint without layout errors',
      (tester) async {
    _installErrorCapture();
    // Multiple device configurations: standard phone, small phone, large text.
    const configs = [
      (name: 'standard', physical: Size(1080, 2400), dpr: 2.8125, scale: 1.0),
      (name: 'small', physical: Size(640, 1280), dpr: 2.0, scale: 1.0),
      (name: 'largeText', physical: Size(1080, 2400), dpr: 2.8125, scale: 1.5),
    ];

    const routeOrder = [
      '/',
      '/welcome',
      '/login',
      '/register',
      '/forgot-password',
      '/forgot-password/otp',
      '/forgot-password/reset',
      '/forgot-password/success',
      '/consent',
      '/permissions',
      '/screening',
      '/processing',
      '/wellness-profile',
      '/dashboard',
    ];

    for (final cfg in configs) {
      tester.view.devicePixelRatio = cfg.dpr;
      tester.view.physicalSize = cfg.physical;
      tester.view.platformDispatcher.textScaleFactorTestValue = cfg.scale;
      addTearDown(tester.view.reset);
      addTearDown(
        tester.view.platformDispatcher.clearTextScaleFactorTestValue,
      );

      for (final path in routeOrder) {
        await tester.pumpWidget(harness(path));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Advance past the splash's automatic navigation timer.
        if (path == '/') {
          await tester.pump(const Duration(seconds: 2));
          await tester.pump(const Duration(milliseconds: 300));
        }

        // Flush any delays/timers so nothing is pending when we move on.
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 300));

        final leaked = _capturedErrors.isNotEmpty ? _errorHead() : '(none)';
        debugPrint('AUDIT ${cfg.name}/$path leaked=$leaked');
        _capturedErrors.clear();
      }
    }
  });
}