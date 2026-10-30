import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/features/ai_coach/presentation/state/chat_controller.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/features/dashboard/presentation/state/progress_controller.dart';
import 'package:mindease/features/future_letters/presentation/state/future_letter_controller.dart';
import 'package:mindease/features/habits/presentation/state/habit_controller.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/physical_wellness/presentation/state/lifestyle_wellness_controller.dart';
import 'package:mindease/features/physical_wellness/presentation/state/physical_wellness_controller.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/features/relax/presentation/state/relax_controller.dart';

/// Mounts [child] one frame after its providers.
///
/// In the real app the `MultiProvider` above the router is built in an earlier
/// frame than any routed screen. `pumpWidget` mounts both at once, so a
/// screen whose `initState` triggers a controller load notifies a provider
/// that is still mid-build, which the framework rejects with "setState() or
/// markNeedsBuild() called during build". Deferring the child one frame
/// reproduces production's ordering.
class _DeferredChild extends StatefulWidget {
  const _DeferredChild({required this.child});

  final Widget child;

  @override
  State<_DeferredChild> createState() => _DeferredChildState();
}

class _DeferredChildState extends State<_DeferredChild> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}

/// Wraps [child] in the same provider scope the real app installs in
/// `lib/app.dart`.
///
/// Layout-audit tests pump the real screens directly instead of `SynoraApp`,
/// so without this every screen that reads a controller through `Provider.of`
/// throws ProviderNotFound and the audit fails before it can check layout.
/// These are genuine controllers backed by the real `FeatureApi`; under
/// `flutter_test` the HTTP client is stubbed, so their initial loads resolve
/// into the controllers' normal empty/error state instead of hanging or
/// escaping as unhandled exceptions.
Widget withAuditProviders(Widget child) {
  return MultiProvider(
    // A fresh key per call: `pumpWidget` updates a same-typed root in place,
    // which would otherwise reuse one controller instance (and its listener
    // registrations) across every audited route.
    key: UniqueKey(),
    providers: [
      ChangeNotifierProvider(create: (_) => MoodController(featureApi)),
      ChangeNotifierProvider(
        create: (_) => JournalController(
          featureApi,
          mediaService: mediaUploadService,
        ),
      ),
      ChangeNotifierProvider(create: (_) => ChatController(featureApi)),
      ChangeNotifierProvider(create: (_) => HabitController(featureApi)),
      ChangeNotifierProvider(create: (_) => ChallengeController(featureApi)),
      ChangeNotifierProvider(
        create: (_) => RecommendationController(featureApi),
      ),
      ChangeNotifierProvider(
        create: (_) => FutureLetterController(featureApi),
      ),
      ChangeNotifierProvider(create: (_) => RelaxController(featureApi)),
      ChangeNotifierProvider(create: (_) => ProgressController(featureApi)),
      ChangeNotifierProvider(
        create: (_) => PhysicalWellnessController(
          featureApi,
          gateway: wearableGateway,
          cache: physicalLocalCache,
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => LifestyleWellnessController(
          featureApi,
          cache: physicalLocalCache,
        ),
      ),
    ],
    child: _DeferredChild(child: child),
  );
}
