import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/mood_tracking/domain/emotion/fer_preloader.dart';

void main() {
  group('FerPreloader', () {
    test('take returns null when nothing is warm', () {
      expect(FerPreloader.take(), isNull);
    });

    test('warmup without engine never throws', () async {
      // Must be safe to call from any screen initState, including tests
      // without asset bundles (load fails silently, take stays null).
      FerPreloader.warmup();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(FerPreloader.take(), isNull);
    });
  });
}
