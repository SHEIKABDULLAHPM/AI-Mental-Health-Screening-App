import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/physical_wellness/presentation/screens/ecg_screen.dart';
import 'package:mindease/shared/widgets/app_button.dart';

class FakeEcgSession implements EcgSession {
  final StreamController<double> controller = StreamController<double>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<String?> start() async {
    startCalls++;
    return null;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Stream<double> get samples => controller.stream;
}

AppButton _startButton(WidgetTester tester) => tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Start'),
    );

void main() {
  testWidgets('unsupported watch shows an honest, non-starting ECG screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: EcgScreen(supportedOverride: false)),
    );

    expect(find.text('ECG is not supported'), findsOneWidget);
    expect(
      find.textContaining('No ECG service or ECG command was found'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No waveform is shown'),
      findsOneWidget,
    );
    expect(_startButton(tester).onPressed, isNull);
    expect(find.textContaining('Start the optical sensor'), findsNothing);
  });

  testWidgets('supported capability without a capture path stays disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: EcgScreen(supportedOverride: true)),
    );

    expect(find.text('ECG capture'), findsOneWidget);
    expect(
      find.textContaining('no verified ECG capture path'),
      findsOneWidget,
    );
    expect(_startButton(tester).onPressed, isNull);
  });

  testWidgets('with a verified session, Start draws only reported samples',
      (tester) async {
    final session = FakeEcgSession();
    await tester.pumpWidget(
      MaterialApp(
        home: EcgScreen(supportedOverride: true, session: session),
      ),
    );

    expect(_startButton(tester).onPressed, isNotNull);
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    expect(session.startCalls, 1);
    expect(find.text('Stop'), findsOneWidget);

    session.controller.add(0.12);
    await tester.pump();
    session.controller.add(-0.04);
    await tester.pump();

    expect(find.text('2 samples'), findsOneWidget);
    expect(
      find.textContaining('not a diagnostic ECG'),
      findsOneWidget,
    );

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(session.stopCalls, 1);
    expect(find.text('Start'), findsOneWidget);
    session.controller.close();
  });
}
