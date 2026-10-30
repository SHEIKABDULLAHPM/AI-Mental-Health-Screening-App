import 'package:go_router/go_router.dart';

import 'package:mindease/features/ai_coach/presentation/screens/ai_coach_home_screen.dart';
import 'package:mindease/features/assessment_history/presentation/screens/assessment_history_screen.dart';
import 'package:mindease/features/ai_coach/presentation/screens/chat_details_screen.dart';
import 'package:mindease/features/ai_coach/presentation/screens/chat_screen.dart';
import 'package:mindease/features/ai_coach/presentation/screens/conversation_history_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/challenge_details_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/challenge_history_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/challenge_result_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/challenges_home_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/game_launcher_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/games_home_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_2048.dart';
import 'package:mindease/features/challenges/presentation/screens/games/game_wrapper.dart';
import 'package:mindease/features/challenges/presentation/screens/games/memory_match_game.dart';
import 'package:mindease/features/challenges/presentation/screens/games/sudoku_game.dart';
import 'package:mindease/features/challenges/presentation/screens/games/tic_tac_toe_game.dart';
import 'package:mindease/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mindease/features/future_letters/presentation/screens/create_future_letter_screen.dart';
import 'package:mindease/features/future_letters/presentation/screens/future_letter_details_screen.dart';
import 'package:mindease/features/future_letters/presentation/screens/future_letters_home_screen.dart';
import 'package:mindease/features/habits/presentation/screens/add_habit_screen.dart';
import 'package:mindease/features/habits/presentation/screens/habit_details_screen.dart';
import 'package:mindease/features/habits/presentation/screens/habit_tracker_home_screen.dart';
import 'package:mindease/features/journal/presentation/screens/create_journal_entry_screen.dart';
import 'package:mindease/features/journal/presentation/screens/edit_journal_entry_screen.dart';
import 'package:mindease/features/journal/presentation/screens/journal_entry_details_screen.dart';
import 'package:mindease/features/journal/presentation/screens/journal_history_screen.dart';
import 'package:mindease/features/journal/presentation/screens/journal_home_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/camera_mood_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_detail_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_history_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_tracking_home_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_result_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_trends_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/record_mood_screen.dart';
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
import 'package:mindease/features/physical_wellness/presentation/screens/physical_wellness_screen.dart';
import 'package:mindease/features/recommendations/presentation/screens/recommendation_activity_screen.dart';
import 'package:mindease/features/recommendations/presentation/screens/recommendation_details_screen.dart';
import 'package:mindease/features/recommendations/presentation/screens/recommendations_home_screen.dart';
import 'package:mindease/features/relax/presentation/screens/activity_player_screen.dart';
import 'package:mindease/features/relax/presentation/screens/relax_home_screen.dart';
import 'package:mindease/features/settings/presentation/settings_screen.dart';

/// Central navigation graph for the app (onboarding → dashboard).
abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const LoginScreen(),
      ),
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
        builder: (_, __) => const PrivacyConsentScreen(),
      ),
      GoRoute(
        path: '/permissions',
        name: 'permissions',
        builder: (_, __) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/screening',
        name: 'screening',
        builder: (_, __) => const ScreeningScreen(),
      ),
      GoRoute(
        path: '/processing',
        name: 'processing',
        builder: (_, __) => const AiProcessingScreen(),
      ),
      GoRoute(
        path: '/wellness-profile',
        name: 'wellnessProfile',
        builder: (_, __) => const WellnessProfileScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (_, __) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/assessment-history',
        name: 'assessmentHistory',
        builder: (_, __) => const AssessmentHistoryScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/mood',
        name: 'mood',
        builder: (_, __) => const MoodTrackingHomeScreen(),
      ),
      GoRoute(
        path: '/mood-record',
        name: 'moodRecord',
        builder: (_, state) => RecordMoodScreen(
          cameraResult: state.extra as CameraMoodResult?,
        ),
      ),
      GoRoute(
        path: '/mood-camera',
        name: 'moodCamera',
        builder: (_, __) => const CameraMoodScreen(),
      ),
      GoRoute(
        path: '/mood-history',
        name: 'moodHistory',
        builder: (_, __) => const MoodHistoryScreen(),
      ),
      GoRoute(
        path: '/mood-detail/:id',
        name: 'moodDetail',
        builder: (_, state) => MoodDetailScreen(
          entryId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/mood-trends',
        name: 'moodTrends',
        builder: (_, __) => const MoodTrendsScreen(),
      ),
      GoRoute(
        path: '/mood-result',
        name: 'moodResult',
        builder: (_, state) {
          final args = state.extra as Map<String, dynamic>?;
          return MoodResultScreen(
            moodId: args?['moodId'] as String? ?? 'okay',
            analysisResult: args?['analysisResult'] as Map<String, dynamic>?,
            emotion: args?['emotion'] as String?,
            note: args?['note'] as String?,
            intensity: args?['intensity'] as int?,
          );
        },
      ),
      GoRoute(
        path: '/journal',
        name: 'journal',
        builder: (_, __) => const JournalHomeScreen(),
      ),
      GoRoute(
        path: '/journal-create',
        name: 'journalCreate',
        builder: (_, __) => const CreateJournalEntryScreen(),
      ),
      GoRoute(
        path: '/journal/:id',
        name: 'journalDetails',
        builder: (_, state) => JournalEntryDetailsScreen(
          entryId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/journal/:id/edit',
        name: 'journalEdit',
        builder: (_, state) => EditJournalEntryScreen(
          entryId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/journal-history',
        name: 'journalHistory',
        builder: (_, __) => const JournalHistoryScreen(),
      ),
      GoRoute(
        path: '/ai-coach',
        name: 'aiCoach',
        builder: (_, __) => const AiCoachHomeScreen(),
      ),
      GoRoute(
        path: '/ai-coach-chat',
        name: 'aiCoachChat',
        builder: (_, state) => ChatScreen(
          title: 'AI Coach',
          initialPrompt: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/ai-coach/:id',
        name: 'aiCoachDetails',
        builder: (_, state) => ChatDetailsScreen(
          conversationId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/ai-coach-history',
        name: 'aiCoachHistory',
        builder: (_, __) => const ConversationHistoryScreen(),
      ),
      GoRoute(
        path: '/recommendations',
        name: 'recommendations',
        builder: (_, __) => const RecommendationsHomeScreen(),
      ),
      GoRoute(
        path: '/recommendations/:id',
        name: 'recommendationDetails',
        builder: (_, state) => RecommendationDetailsScreen(
          recommendationId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/challenges',
        name: 'challenges',
        builder: (_, __) => const ChallengesHomeScreen(),
      ),
      // Static challenge sub-routes MUST come before /challenges/:id to avoid
      // the parameterized route shadowing them.
      GoRoute(
        path: '/challenges/history',
        name: 'challengeHistory',
        builder: (_, __) => const ChallengeHistoryScreen(),
      ),
      GoRoute(
        path: '/challenges/games',
        name: 'challengeGames',
        builder: (_, __) => const GamesHomeScreen(),
      ),
      GoRoute(
        path: '/challenges/game/2048',
        name: 'game2048',
        builder: (_, state) => GameChallengeWrapper(
          challengeId: state.uri.queryParameters['challengeId'],
          child: const Game2048(),
        ),
      ),
      GoRoute(
        path: '/challenges/game/sudoku',
        name: 'gameSudoku',
        builder: (_, state) => GameChallengeWrapper(
          challengeId: state.uri.queryParameters['challengeId'],
          child: const SudokuGame(),
        ),
      ),
      GoRoute(
        path: '/challenges/game/tic-tac-toe',
        name: 'gameTicTacToe',
        builder: (_, state) => GameChallengeWrapper(
          challengeId: state.uri.queryParameters['challengeId'],
          child: const TicTacToeGame(),
        ),
      ),
      GoRoute(
        path: '/challenges/game/memory',
        name: 'gameMemory',
        builder: (_, state) => GameChallengeWrapper(
          challengeId: state.uri.queryParameters['challengeId'],
          child: const MemoryMatchGame(),
        ),
      ),
      // Parameterized challenge sub-routes (/:id/game and /:id/result) come
      // after static routes but before the catch-all /:id details route.
      GoRoute(
        path: '/challenges/:id/game',
        name: 'challengeGame',
        builder: (_, state) => GameChallengeWrapper(
          challengeId: state.pathParameters['id']!,
          child: GameLauncherScreen(
            challengeId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/challenges/:id/result',
        name: 'challengeResult',
        builder: (_, state) {
          final args = state.extra as Map<String, dynamic>?;
          return ChallengeResultScreen(
            challengeTitle: args?['title'] as String? ?? 'Challenge',
            pointsEarned: args?['points'] as int? ?? 0,
            badgeLabel: args?['badge'] as String?,
            streakDays: args?['streak'] as int?,
            message: args?['message'] as String?,
          );
        },
      ),
      // The catch-all /:id details route comes LAST so it doesn't shadow
      // any static or sub-parameterized challenge routes.
      GoRoute(
        path: '/challenges/:id',
        name: 'challengeDetails',
        builder: (_, state) => ChallengeDetailsScreen(
          challengeId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/habits',
        name: 'habits',
        builder: (_, __) => const HabitTrackerHomeScreen(),
      ),
      GoRoute(
        path: '/habits/add',
        name: 'habitAdd',
        builder: (_, __) => const AddHabitScreen(),
      ),
      GoRoute(
        path: '/habits/:id',
        name: 'habitDetails',
        builder: (_, state) => HabitDetailsScreen(
          habitId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/activities/:slug',
        name: 'recommendationActivity',
        builder: (_, state) {
          final args = state.extra as Map<String, dynamic>?;
          return RecommendationActivityScreen(
            recommendationId: args?['recommendationId'] as String? ?? '',
            title: args?['title'] as String? ?? 'Activity',
            description: args?['description'] as String? ?? '',
            category: args?['category'] as String?,
            duration: args?['duration'] as String?,
            difficulty: args?['difficulty'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/relax',
        name: 'relax',
        builder: (_, __) => const RelaxHomeScreen(),
      ),
      GoRoute(
        path: '/relax/:id',
        name: 'relaxActivity',
        builder: (_, state) => ActivityPlayerScreen(
          activityId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/letters',
        name: 'letters',
        builder: (_, __) => const FutureLettersHomeScreen(),
      ),
      GoRoute(
        path: '/letters/create',
        name: 'lettersCreate',
        builder: (_, __) => const CreateFutureLetterScreen(),
      ),
      GoRoute(
        path: '/letters/:id',
        name: 'letterDetails',
        builder: (_, state) => FutureLetterDetailsScreen(
          letterId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/physical-wellness',
        name: 'physicalWellness',
        builder: (_, __) => const PhysicalWellnessScreen(),
      ),
    ],
    errorBuilder: (_, __) => const SplashScreen(),
  );
}
