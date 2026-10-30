import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/shared/widgets/combined_insight_card.dart';

MindeaseCombinedInsight _insight({
  String generatedBy = 'llm',
  bool safetyFlag = false,
  MindeaseInsightCoverage? coverage,
}) {
  return MindeaseCombinedInsight(
    available: true,
    narrative:
        'Your recent check-in points to moderate stress with supporting your mood '
        'as the main focus.',
    suggestions: const [
      MindeaseInsightSuggestion(
        title: 'Keep a repeatable wind-down',
        description: 'Choose a short routine before bed.',
        category: 'SLEEP',
      ),
    ],
    generatedBy: generatedBy,
    safetyFlag: safetyFlag,
    note: 'This is guidance, not a diagnosis.',
    coverage: coverage ??
        const MindeaseInsightCoverage(
          windowDays: 14,
          daysWithActivity: 6,
          daysWithSleep: 4,
          daysWithHydration: 5,
          moodCheckins: 3,
        ),
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('MindeaseAssessmentSummary', () {
    test('parses stored assessment metadata and answered sections', () {
      final summary = MindeaseAssessmentSummary.fromJson({
        'id': 'a1',
        'status': 'COMPLETED',
        'startedAt': '2026-10-01T10:00:00Z',
        'completedAt': '2026-10-01T10:20:00Z',
        'assessments': {
          'phq9': [1, 2, 0, 1, 0, 2, 1, 0, 3],
          'gad7': [1, 1, 0, 2, 1, 0, 1],
          'pss': <int>[],
        },
      });

      expect(summary.id, 'a1');
      expect(summary.isCompleted, isTrue);
      expect(summary.recordedAt, DateTime.utc(2026, 10, 1, 10, 20));
      expect(summary.questionnaireCodes, ['phq9', 'gad7']);
      expect(summary.questionnaireCodes, isNot(contains('pss')));
    });

    test('in-progress assessment has no completion date', () {
      final summary = MindeaseAssessmentSummary.fromJson({
        'id': 'a2',
        'status': 'IN_PROGRESS',
        'updatedAt': '2026-10-02T09:00:00Z',
      });

      expect(summary.isCompleted, isFalse);
      expect(summary.completedAt, isNull);
      expect(summary.recordedAt, DateTime.utc(2026, 10, 2, 9));
      expect(summary.questionnaireCodes, isEmpty);
    });
  });

  group('MindeaseCombinedInsight', () {
    test('parses the AI-wording path with server coverage', () {
      final insight = MindeaseCombinedInsight.fromJson({
        'available': true,
        'narrative': 'A grounded combined reflection.',
        'generatedBy': 'llm',
        'safetyFlag': true,
        'cached': true,
        'note': 'Guidance, not a diagnosis.',
        'suggestions': [
          {
            'title': 'Reach out today',
            'description': 'Tell someone you trust.',
            'category': 'SUPPORT',
          },
        ],
        'coverage': {
          'windowDays': 14,
          'daysWithActivity': 6,
          'daysWithSleep': 0,
          'daysWithHydration': 5,
          'moodCheckins': 3,
        },
      });

      expect(insight.available, isTrue);
      expect(insight.isAiWording, isTrue);
      expect(insight.safetyFlag, isTrue);
      expect(insight.cached, isTrue);
      expect(insight.suggestions.single.category, 'SUPPORT');
      expect(insight.coverage!.daysWithSleep, 0);
      expect(insight.coverage!.windowDays, 14);
    });

    test('rule-based output is never labelled as AI wording', () {
      final insight = MindeaseCombinedInsight.fromJson({
        'available': true,
        'narrative': 'Rule-based grounded reflection.',
        'generatedBy': 'rules',
      });

      expect(insight.isAiWording, isFalse);
      expect(insight.safetyFlag, isFalse);
      expect(insight.coverage, isNull);
    });

    test('pre-onboarding response is simply unavailable', () {
      final insight = MindeaseCombinedInsight.fromJson({
        'available': false,
        'note': 'Complete your screening to unlock a combined insight.',
      });

      expect(insight.available, isFalse);
      expect(insight.isAiWording, isFalse);
    });
  });

  group('CombinedInsightCard', () {
    testWidgets('labels AI wording honestly and shows coverage',
        (tester) async {
      await tester
          .pumpWidget(_harness(CombinedInsightCard(insight: _insight())));

      expect(find.text('Mind–body insight'), findsOneWidget);
      expect(find.text('AI-personalised'), findsOneWidget);
      expect(find.text('Keep a repeatable wind-down'), findsOneWidget);
      expect(
        find.text(
            'Last 14 days: activity 6 · sleep 4 nights · hydration 5 · mood 3'),
        findsOneWidget,
      );
      expect(find.text('This is guidance, not a diagnosis.'), findsOneWidget);
    });

    testWidgets('rule-based text is not presented as AI', (tester) async {
      await tester.pumpWidget(
        _harness(CombinedInsightCard(insight: _insight(generatedBy: 'rules'))),
      );

      expect(find.text('Based on your data'), findsOneWidget);
      expect(find.text('AI-personalised'), findsNothing);
    });

    testWidgets('renders nothing when the insight is unavailable',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const CombinedInsightCard(
              insight: MindeaseCombinedInsight.unavailable),
        ),
      );

      expect(find.text('Mind–body insight'), findsNothing);
    });
  });
}
