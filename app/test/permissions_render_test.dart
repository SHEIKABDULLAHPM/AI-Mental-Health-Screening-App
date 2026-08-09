import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mindease/core/theme/app_theme.dart';
import 'package:mindease/features/onboarding/permissions/permissions_screen.dart';

Widget harness() {
  final router = GoRouter(
    initialLocation: '/permissions',
    routes: [
      GoRoute(
        path: '/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(path: '/screening', builder: (context, state) => const Scaffold()),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
  );
}

void main() {
  testWidgets('permissions screen renders Allow buttons in cards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('A little goes a long way'), findsOneWidget);
    expect(find.text('Allow'), findsNWidgets(4));
    expect(find.text('0/4 permissions'), findsOneWidget);

    final btnRect = tester.getRect(find.text('Allow').first);
    expect(btnRect.width, greaterThan(0));
    expect(btnRect.height, greaterThan(0));
    debugPrint('GEOM permissions Allow button rect=$btnRect');

    await tester.binding.setSurfaceSize(null);
  });
}