import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/router/app_router.dart';
import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/ai_coach/presentation/state/chat_controller.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/features/future_letters/presentation/state/future_letter_controller.dart';
import 'package:mindease/features/habits/presentation/state/habit_controller.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/features/dashboard/presentation/state/progress_controller.dart';
import 'package:mindease/features/relax/presentation/state/relax_controller.dart';

/// Root widget: wires the theme and the app router.
class SynoraApp extends StatelessWidget {
  const SynoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MoodController(featureApi)),
        ChangeNotifierProvider(create: (_) => JournalController(featureApi, mediaService: mediaUploadService)),
        ChangeNotifierProvider(create: (_) => ChatController(featureApi)),
        ChangeNotifierProvider(create: (_) => HabitController(featureApi)),
        ChangeNotifierProvider(create: (_) => ChallengeController(featureApi)),
        ChangeNotifierProvider(create: (_) => RecommendationController(featureApi)),
        ChangeNotifierProvider(create: (_) => FutureLetterController(featureApi)),
        ChangeNotifierProvider(create: (_) => RelaxController(featureApi)),
        ChangeNotifierProvider(create: (_) => ProgressController(featureApi)),
      ],
      child: MaterialApp.router(
        title: 'SYNORA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: AppRouter.router,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeOutCubic,
      ),
    );
  }
}
