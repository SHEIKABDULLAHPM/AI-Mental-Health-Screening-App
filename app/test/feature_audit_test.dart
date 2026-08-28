import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/ai_coach/presentation/screens/ai_coach_home_screen.dart';
import 'package:mindease/features/ai_coach/presentation/screens/chat_details_screen.dart';
import 'package:mindease/features/ai_coach/presentation/screens/chat_screen.dart';
import 'package:mindease/features/ai_coach/presentation/screens/conversation_history_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/challenge_details_screen.dart';
import 'package:mindease/features/challenges/presentation/screens/challenges_home_screen.dart';
import 'package:mindease/features/future_letters/presentation/screens/create_future_letter_screen.dart';
import 'package:mindease/features/future_letters/presentation/screens/future_letter_details_screen.dart';
import 'package:mindease/features/future_letters/presentation/screens/future_letters_home_screen.dart';
import 'package:mindease/features/habits/presentation/screens/add_habit_screen.dart';
import 'package:mindease/features/habits/presentation/screens/habit_details_screen.dart';
import 'package:mindease/features/habits/presentation/screens/habit_tracker_home_screen.dart';
import 'package:mindease/features/journal/presentation/screens/create_journal_entry_screen.dart';
import 'package:mindease/features/journal/presentation/screens/journal_entry_details_screen.dart';
import 'package:mindease/features/journal/presentation/screens/journal_history_screen.dart';
import 'package:mindease/features/journal/presentation/screens/journal_home_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_history_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_tracking_home_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/mood_trends_screen.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/record_mood_screen.dart';
import 'package:mindease/features/recommendations/presentation/screens/recommendation_details_screen.dart';
import 'package:mindease/features/recommendations/presentation/screens/recommendations_home_screen.dart';
import 'package:mindease/features/relax/presentation/screens/activity_player_screen.dart';
import 'package:mindease/features/relax/presentation/screens/relax_home_screen.dart';

Widget harness(String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/mood', builder: (c, s) => const MoodTrackingHomeScreen()),
      GoRoute(path: '/mood-record', builder: (c, s) => const RecordMoodScreen()),
      GoRoute(path: '/mood-history', builder: (c, s) => const MoodHistoryScreen()),
      GoRoute(path: '/mood-trends', builder: (c, s) => const MoodTrendsScreen()),
      GoRoute(path: '/journal', builder: (c, s) => const JournalHomeScreen()),
      GoRoute(
        path: '/journal-create',
        builder: (c, s) => const CreateJournalEntryScreen(),
      ),
      GoRoute(
        path: '/journal/j1',
        builder: (c, s) => const JournalEntryDetailsScreen(entryId: 'j1'),
      ),
      GoRoute(
        path: '/journal-history',
        builder: (c, s) => const JournalHistoryScreen(),
      ),
      GoRoute(path: '/ai-coach', builder: (c, s) => const AiCoachHomeScreen()),
      GoRoute(path: '/ai-coach-chat', builder: (c, s) => const ChatScreen()),
      GoRoute(
        path: '/ai-coach/c1',
        builder: (c, s) => const ChatDetailsScreen(conversationId: 'c1'),
      ),
      GoRoute(
        path: '/ai-coach-history',
        builder: (c, s) => const ConversationHistoryScreen(),
      ),
      GoRoute(
        path: '/recommendations',
        builder: (c, s) => const RecommendationsHomeScreen(),
      ),
      GoRoute(
        path: '/recommendations/r1',
        builder: (c, s) => const RecommendationDetailsScreen(recommendationId: 'r1'),
      ),
      GoRoute(
        path: '/challenges',
        builder: (c, s) => const ChallengesHomeScreen(),
      ),
      GoRoute(
        path: '/challenges/ch1',
        builder: (c, s) => const ChallengeDetailsScreen(challengeId: 'ch1'),
      ),
      GoRoute(path: '/habits', builder: (c, s) => const HabitTrackerHomeScreen()),
      GoRoute(path: '/habits/add', builder: (c, s) => const AddHabitScreen()),
      GoRoute(
        path: '/habits/h1',
        builder: (c, s) => const HabitDetailsScreen(habitId: 'h1'),
      ),
      GoRoute(path: '/relax', builder: (c, s) => const RelaxHomeScreen()),
      GoRoute(
        path: '/relax/re1',
        builder: (c, s) => const ActivityPlayerScreen(activityId: 're1'),
      ),
      GoRoute(
        path: '/letters',
        builder: (c, s) => const FutureLettersHomeScreen(),
      ),
      GoRoute(
        path: '/letters/create',
        builder: (c, s) => const CreateFutureLetterScreen(),
      ),
      GoRoute(
        path: '/letters/f1',
        builder: (c, s) => const FutureLetterDetailsScreen(letterId: 'f1'),
      ),
    ],
  );
  return MaterialApp.router(theme: AppTheme.light(), routerConfig: router);
}

final List<String> _capturedErrors = [];

void _installErrorCapture() {
  _capturedErrors.clear();
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    _capturedErrors.add(details.toString());
    original?.call(details);
  };
}

void main() {
  testWidgets(
    'audit: all Core Features screens paint without layout errors',
    (tester) async {
      _installErrorCapture();
      const configs = [
        (name: 'standard', physical: Size(1080, 2400), dpr: 2.8125, scale: 1.0),
        (name: 'small', physical: Size(640, 1280), dpr: 2.0, scale: 1.0),
        (name: 'largeText', physical: Size(1080, 2400), dpr: 2.8125, scale: 1.5),
      ];

      const routeOrder = [
        '/mood',
        '/mood-record',
        '/mood-history',
        '/mood-trends',
        '/journal',
        '/journal-create',
        '/journal/j1',
        '/journal-history',
        '/ai-coach',
        '/ai-coach-chat',
        '/ai-coach/c1',
        '/ai-coach-history',
        '/recommendations',
        '/recommendations/r1',
        '/challenges',
        '/challenges/ch1',
        '/habits',
        '/habits/add',
        '/habits/h1',
        '/relax',
        '/relax/re1',
        '/letters',
        '/letters/create',
        '/letters/f1',
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

          // Flush simulated loading delays so no timers are left pending.
          await tester.pump(const Duration(seconds: 6));
          await tester.pump(const Duration(milliseconds: 300));

          final leaked =
              _capturedErrors.isNotEmpty ? _capturedErrors.join('\n') : '';
          expect(
            leaked,
            isEmpty,
            reason: 'layout/assertion errors on $path (${cfg.name})',
          );
          _capturedErrors.clear();
        }
      }
    },
  );
}
