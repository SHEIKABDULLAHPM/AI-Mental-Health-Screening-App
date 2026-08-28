import 'dart:async';

/// Short async delay used by UI-only screens to demonstrate the loading
/// state. Remove once real repositories drive these screens.
Future<void> simulateLoad({
  Duration duration = const Duration(milliseconds: 650),
}) =>
    Future<void>.delayed(duration);
