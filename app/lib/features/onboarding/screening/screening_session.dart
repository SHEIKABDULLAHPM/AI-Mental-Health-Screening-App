import 'screening_controller.dart';
import 'wellness_engine.dart';

/// In-memory single-run session bridging screening → processing → profile.
class ScreeningSession {
  ScreeningSession._();

  static final ScreeningController controller = ScreeningController();
  static WellnessReport? report;
  static String? firstName;

  static void reset() {
    controller.stepIndex = 0;
    controller.questionIndex = 0;
    report = null;
  }
}
