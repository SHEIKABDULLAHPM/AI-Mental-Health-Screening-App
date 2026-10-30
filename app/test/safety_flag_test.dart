import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/shared/widgets/safety_support_card.dart';

void main() {
  test('profile and dashboard parse the server safety flag', () {
    final profile = MindeaseProfile.fromJson({
      'id': 'p1',
      'status': 'COMPLETED',
      'safetyFlag': true,
    });
    final dashboard = MindeaseDashboard.fromJson({
      'aiReady': true,
      'aiStatus': 'COMPLETED',
      'safetyFlag': true,
    });

    expect(profile.safetyFlag, isTrue);
    expect(dashboard.safetyFlag, isTrue);
  });

  test('absent safety flag defaults to false', () {
    final profile =
        MindeaseProfile.fromJson({'id': 'p1', 'status': 'COMPLETED'});
    final dashboard = MindeaseDashboard.fromJson({'aiReady': false});

    expect(profile.safetyFlag, isFalse);
    expect(dashboard.safetyFlag, isFalse);
  });

  testWidgets('support card renders non-diagnostic escalation copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SafetySupportCard()),
      ),
    );

    expect(find.text('You deserve support right now'), findsOneWidget);
    expect(
      find.textContaining('thoughts of self-harm'),
      findsOneWidget,
    );
    expect(find.textContaining('not a diagnosis'), findsOneWidget);
  });
}
