import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/future_letters/presentation/state/future_letter_controller.dart';
import 'package:mindease/features/future_letters/presentation/widgets/future_letter_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Future Letters home: scheduled, delivered and opened letters.
class FutureLettersHomeScreen extends StatefulWidget {
  const FutureLettersHomeScreen({super.key});

  @override
  State<FutureLettersHomeScreen> createState() =>
      _FutureLettersHomeScreenState();
}

class _FutureLettersHomeScreenState extends State<FutureLettersHomeScreen> {
  @override
  void initState() {
    super.initState();
    final ctrl = context.read<FutureLetterController>();
    ctrl.loadScheduled();
    ctrl.loadDelivered();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<FutureLetterController>();
    final scheduled = ctrl.scheduledLetters;
    final delivered = ctrl.deliveredLetters;

    return FeatureScaffold(
      title: 'Future Letters',
      actions: [
        IconButton(
          tooltip: 'Write a letter',
          onPressed: () => context.push('/letters/create'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      body: ctrl.loading && scheduled.isEmpty && delivered.isEmpty
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        const Icon(Icons.mail_rounded, size: 40),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Write a letter today. Read it when you need it '
                            'most — days, months or years from now.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (scheduled.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Scheduled',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...scheduled.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: FutureLetterCard(
                        letter: l,
                        onTap: () => context.push('/letters/${l.id}'),
                      ),
                    ),
                  ),
                ],
                if (delivered.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Delivered & opened',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...delivered.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: FutureLetterCard(
                        letter: l,
                        onTap: () => context.push('/letters/${l.id}'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
