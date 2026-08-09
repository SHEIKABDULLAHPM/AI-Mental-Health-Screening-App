import 'package:go_router/go_router.dart';

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
import 'package:mindease/features/onboarding/screening/wellness_profile_screen.dart';
import 'package:mindease/features/onboarding/splash/splash_screen.dart';
import 'package:mindease/features/onboarding/welcome/welcome_screen.dart';

/// Central navigation graph for the app (onboarding → dashboard).
abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
          path: '/', name: 'splash', builder: (_, __) => const SplashScreen(),),
      GoRoute(
          path: '/welcome',
          name: 'welcome',
          builder: (_, __) => const WelcomeScreen(),),
      GoRoute(
          path: '/register',
          name: 'register',
          builder: (_, __) => const RegisterScreen(),),
      GoRoute(
          path: '/login',
          name: 'login',
          builder: (_, __) => const LoginScreen(),),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        builder: (_, __) => const ForgotPasswordEmailScreen(),
      ),
      GoRoute(
        path: '/forgot-password/otp',
        name: 'otp',
        builder: (_, __) => const OtpVerificationScreen(),
      ),
      GoRoute(
        path: '/forgot-password/reset',
        name: 'resetPassword',
        builder: (_, __) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/forgot-password/success',
        name: 'resetSuccess',
        builder: (_, __) => const ResetSuccessScreen(),
      ),
      GoRoute(
          path: '/consent',
          name: 'consent',
          builder: (_, __) => const PrivacyConsentScreen(),),
      GoRoute(
          path: '/permissions',
          name: 'permissions',
          builder: (_, __) => const PermissionsScreen(),),
      GoRoute(
          path: '/screening',
          name: 'screening',
          builder: (_, __) => const ScreeningScreen(),),
      GoRoute(
          path: '/processing',
          name: 'processing',
          builder: (_, __) => const AiProcessingScreen(),),
      GoRoute(
        path: '/wellness-profile',
        name: 'wellnessProfile',
        builder: (_, __) => const WellnessProfileScreen(),
      ),
      GoRoute(
          path: '/dashboard',
          name: 'dashboard',
          builder: (_, __) => const DashboardScreen(),),
    ],
    errorBuilder: (_, __) => const SplashScreen(),
  );
}
