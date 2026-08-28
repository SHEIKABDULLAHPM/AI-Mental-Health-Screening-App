import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_backdrop.dart';

/// Shared chrome for core-feature screens: a transparent app bar plus the
/// soft gradient backdrop, with content constrained to a comfortable column
/// width on larger Android screens.
class FeatureScaffold extends StatelessWidget {
  const FeatureScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomBar,
    this.backdropIntensity = 0.55,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomBar;
  final double backdropIntensity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: AppBackdrop(
        intensity: backdropIntensity,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: body,
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// Scroll container used by most feature screens: consistent horizontal
/// padding on top of [FeatureScaffold].
class FeatureBody extends StatelessWidget {
  const FeatureBody({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
      child: child,
    );
  }
}
