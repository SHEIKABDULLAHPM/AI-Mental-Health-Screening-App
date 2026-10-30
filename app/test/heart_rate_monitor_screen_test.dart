import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/physical_wellness/data/wearable_gateway.dart';
import 'package:mindease/features/physical_wellness/presentation/screens/heart_rate_monitor_screen.dart';
import 'package:mindease/shared/widgets/app_button.dart';

class FakeLiveHeartRateSession implements LiveHeartRateSession {
  FakeLiveHeartRateSession({this.startError});

  /// Mutable so a test can fail only the restart, after a successful start.
  String? startError;
  final StreamController<LiveHeartRateSample> controller =
      StreamController<LiveHeartRateSample>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;
  List<LiveHeartRateSample>? saved;

  @override
  Future<String?> start() async {
    startCalls++;
    return startError;
  }

  @override
  Future<bool> stop() async {
    stopCalls++;
    return true;
  }

  @override
  Stream<LiveHeartRateSample> get samples => controller.stream;

  @override
  Future<int?> save(List<LiveHeartRateSample> samples) async {
    saved = samples;
    return samples.length;
  }
}

LiveHeartRateSample sample(int bpm, int second) => LiveHeartRateSample(
      bpm: bpm,
      timestamp: DateTime.utc(2026, 10, 26, 12, 0, second),
      recordedAt: DateTime.utc(2026, 10, 26, 12, 0, second),
      measurementType: 'DEVICE_MEASURED',
      source: 'FITPRO',
    );

void main() {
  testWidgets('shows no reading until the band reports one', (tester) async {
    final session = FakeLiveHeartRateSession();
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('bpm (no sample yet)'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    expect(session.startCalls, 1);
    expect(find.text('Stop'), findsOneWidget);
    // Still no fabricated value: the sensor has not sent anything.
    expect(find.text('—'), findsOneWidget);
    expect(
      find.textContaining('Waiting for the watch to report a beat'),
      findsOneWidget,
    );
  });

  testWidgets('renders only the samples the band emits', (tester) async {
    final session = FakeLiveHeartRateSession();
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    session.controller.add(sample(68, 1));
    await tester.pump();
    session.controller.add(sample(72, 2));
    await tester.pump();

    expect(find.text('72'), findsOneWidget);
    expect(find.text('2 samples · 68–72 bpm'), findsOneWidget);
    session.controller.close();
  });

  testWidgets('stop persists the live session through the seam',
      (tester) async {
    final session = FakeLiveHeartRateSession();
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    session.controller.add(sample(66, 1));
    await tester.pump();

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(session.stopCalls, 1);
    expect(session.saved, hasLength(1));
    expect(session.saved!.single.bpm, 66);
    expect(find.textContaining('1 live reading queued for sync'),
        findsOneWidget);
    session.controller.close();
  });

  testWidgets('leaving the screen stops a running session', (tester) async {
    final session = FakeLiveHeartRateSession();
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(session.stopCalls, 0);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    // The optical sensor must not keep running after the screen is gone.
    expect(session.stopCalls, 1);
    session.controller.close();
  });

  testWidgets('a failed start is explained, never shown as measuring',
      (tester) async {
    final session = FakeLiveHeartRateSession(
      startError: 'Could not start live measurement.',
    );
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Could not start live measurement.'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    session.controller.close();
  });

  testWidgets('a failed restart keeps the readings already shown',
      (tester) async {
    final session = FakeLiveHeartRateSession();
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    session.controller.add(sample(71, 1));
    await tester.pump();
    expect(find.text('71'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('71'), findsOneWidget);

    // The band refuses the next session (out of range, busy link, …).
    session.startError = 'Could not start live measurement.';
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Could not start live measurement.'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    // The confirmed earlier reading must survive the failed restart.
    expect(find.text('71'), findsOneWidget);
    expect(find.text('1 samples · 71–71 bpm'), findsOneWidget);
    session.controller.close();
  });

  testWidgets('the Start button is present when the device lacks support',
      (tester) async {
    // The screen itself does not hide the action; the controller answers with
    // an actionable message when no watch is paired.
    final session = FakeLiveHeartRateSession(
      startError: 'Connect your watch first.',
    );
    await tester.pumpWidget(
      MaterialApp(home: HeartRateMonitorScreen(session: session)),
    );

    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Start'),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your watch first.'), findsOneWidget);
    session.controller.close();
  });
}
