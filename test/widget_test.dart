import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_mental_health_app/app.dart';

void main() {
  testWidgets('App boots to splash then shows welcome for new users', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MindEaseApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('MindEase'), findsWidgets);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Welcome to MindEase'), findsOneWidget);
  });

  testWidgets('Existing onboarded user lands directly on dashboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mindease_onboarding_complete': true,
    });

    await tester.pumpWidget(const MindEaseApp());
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Quick Access'), findsOneWidget);
  });
}
