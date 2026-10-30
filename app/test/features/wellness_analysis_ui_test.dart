import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/core/api/models.dart';
import 'package:mindease/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/data/physical_local_cache.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_api.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_models.dart';
import 'package:mindease/features/physical_wellness/presentation/screens/physical_wellness_screen.dart';
import 'package:mindease/features/physical_wellness/presentation/state/lifestyle_wellness_controller.dart';
import 'package:mindease/shared/widgets/wellness_analysis_result_card.dart';

class _FakeLifestyleApi implements PhysicalWellnessApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLifestyleCache implements PhysicalLocalCache {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _harness(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('UnifiedAiInsightCard', () {
    testWidgets('renders insight narrative and clickable action button when idle', (tester) async {
      var triggered = false;
      await tester.pumpWidget(
        _harness(
          UnifiedAiInsightCard(
            insight: 'Your mood check-ins correlate with better sleep regularity.',
            loading: false,
            onAnalyzeCombined: () => triggered = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Latest AI Insight'), findsOneWidget);
      expect(find.text('Holistic mental & physical analysis'), findsOneWidget);
      expect(find.text('Your mood check-ins correlate with better sleep regularity.'), findsOneWidget);
      expect(find.text('Analyze Combined Wellness'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Analyze Combined Wellness'));
      expect(triggered, isTrue);
    });

    testWidgets('renders loading spinner, progress text and disables button when running', (tester) async {
      await tester.pumpWidget(
        _harness(
          UnifiedAiInsightCard(
            insight: 'Previous insight text here.',
            loading: true,
            onAnalyzeCombined: () {},
          ),
        ),
      );

      expect(find.text('Latest AI Insight'), findsOneWidget);
      expect(find.text('Analyzing your combined wellness data with AI...'), findsOneWidget);
      expect(find.text('Analyzing Combined Wellness...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('MindBodyInsightCard in Physical Wellness', () {
    testWidgets('renders Mind–Body Insight title, narrative, suggestions, and AI badge', (tester) async {
      final controller = LifestyleWellnessController(_FakeLifestyleApi(), cache: _FakeLifestyleCache());
      const insight = MindeaseCombinedInsight(
        available: true,
        narrative: 'Consistent evening sleep correlates with lower daytime stress check-ins.',
        generatedBy: 'llm',
        suggestions: [
          MindeaseInsightSuggestion(
            title: 'Sleep Routine',
            description: 'Wind down 30 mins before bed.',
          ),
        ],
      );

      await tester.pumpWidget(
        _harness(
          MindBodyInsightCard(
            lifestyle: controller,
            stale: false,
            mindBodyInsight: insight,
            loadingMindBody: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mind–Body Insight'), findsOneWidget);
      expect(find.text('Consistent evening sleep correlates with lower daytime stress check-ins.'), findsOneWidget);
      expect(find.text('AI Personalised'), findsOneWidget);
      expect(find.text('Sleep Routine'), findsOneWidget);
      expect(find.text('Wind down 30 mins before bed.'), findsOneWidget);
    });

    testWidgets('renders loading state when loadingMindBody is true', (tester) async {
      final controller = LifestyleWellnessController(_FakeLifestyleApi(), cache: _FakeLifestyleCache());

      await tester.pumpWidget(
        _harness(
          MindBodyInsightCard(
            lifestyle: controller,
            stale: false,
            mindBodyInsight: null,
            loadingMindBody: true,
          ),
        ),
      );

      expect(find.text('Mind–Body Insight'), findsOneWidget);
      expect(find.text('Analyzing mind–body correlations…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('GoalRow AI vs Custom Target Distinction', () {
    testWidgets('distinguishes AI-recommended targets with AI Target badge', (tester) async {
      const aiGoal = GoalProgress(
        metric: 'dailySteps',
        label: 'Daily steps',
        unit: 'steps',
        period: 'DAILY',
        dataAvailable: true,
        target: 8000,
        current: 5400,
        progress: 0.675,
        targetSource: 'AI_RECOMMENDED',
      );

      await tester.pumpWidget(_harness(const GoalRow(item: aiGoal)));
      await tester.pumpAndSettle();

      expect(find.text('Daily steps'), findsOneWidget);
      expect(find.text('AI Target'), findsOneWidget);
      expect(find.text('5400 / 8000 steps'), findsOneWidget);
    });

    testWidgets('distinguishes user-entered targets with Custom Target badge', (tester) async {
      const userGoal = GoalProgress(
        metric: 'dailySleepMinutes',
        label: 'Sleep duration',
        unit: 'min',
        period: 'DAILY',
        dataAvailable: true,
        target: 480,
        current: 450,
        progress: 0.937,
        targetSource: 'USER',
      );

      await tester.pumpWidget(_harness(const GoalRow(item: userGoal)));
      await tester.pumpAndSettle();

      expect(find.text('Sleep duration'), findsOneWidget);
      expect(find.text('Custom Target'), findsOneWidget);
      expect(find.text('450 / 480 min'), findsOneWidget);
    });
  });

  group('WellnessAnalysisResultCard & GoalTargetSuggestion', () {
    testWidgets('renders AI-recommended targets and advice correctly', (tester) async {
      final result = WellnessAnalysisResult(
        title: 'Combined Wellness Analysis',
        available: true,
        generatedBy: 'llm',
        analyzedAt: DateTime.now(),
        narrative: 'Your physical activity positively impacts your mood.',
        goalTargetSuggestions: const [
          GoalTargetSuggestion(
            metric: 'dailySteps',
            value: 8000,
            unit: 'steps',
            rationale: 'Gradual increase from 6000 to boost energy and mood.',
          ),
          GoalTargetSuggestion(
            metric: 'dailySleepMinutes',
            value: 480,
            unit: 'min',
            rationale: '8 hours of consistent sleep improves stress resilience.',
          ),
        ],
        advice: const [
          WellnessAnalysisAdvice(
            title: 'Morning Walk',
            description: 'Step outside for 15 minutes of natural sunlight.',
          ),
        ],
      );

      await tester.pumpWidget(_harness(WellnessAnalysisResultCard(result: result)));
      await tester.pumpAndSettle();

      expect(find.text('Combined Wellness Analysis'), findsOneWidget);
      expect(find.text('Your physical activity positively impacts your mood.'), findsOneWidget);
      expect(find.text('AI RECOMMENDED TARGETS'), findsOneWidget);
      expect(find.text('AI Target'), findsNWidgets(2));
      expect(find.text('Daily steps target'), findsOneWidget);
      expect(find.text('8000 steps'), findsOneWidget);
      expect(find.text('Gradual increase from 6000 to boost energy and mood.'), findsOneWidget);
      expect(find.text('Daily sleep target'), findsOneWidget);
      expect(find.text('480 min'), findsOneWidget);
      expect(find.text('Morning Walk'), findsOneWidget);
    });
  });
}
