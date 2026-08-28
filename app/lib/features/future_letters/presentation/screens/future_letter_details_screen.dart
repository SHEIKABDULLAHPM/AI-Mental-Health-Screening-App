import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/future_letters/data/future_letter.dart';
import 'package:mindease/features/future_letters/presentation/state/future_letter_controller.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Full view of a future letter and its delivery status.
class FutureLetterDetailsScreen extends StatefulWidget {
  const FutureLetterDetailsScreen({super.key, required this.letterId});

  final String letterId;

  @override
  State<FutureLetterDetailsScreen> createState() =>
      _FutureLetterDetailsScreenState();
}

class _FutureLetterDetailsScreenState
    extends State<FutureLetterDetailsScreen> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<FutureLetterController>().loadLetters();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<FutureLetterController>();
    final letter = ctrl.letters
        .where((l) => l.id == widget.letterId)
        .firstOrNull;
    return FeatureScaffold(
      title: 'Letter',
      body: ctrl.loading || letter == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      letter.status.icon,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  letter.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${letter.status.label} · '
                  '${DateFormat.yMMMd().format(letter.scheduledDate)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dear ${letter.recipient},',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          letter.content,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Written with care',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (letter.status == LetterStatus.opened && !_opened)
                  Center(
                    child: FilledButton.icon(
                      onPressed: () {
                        ctrl.openLetter(letter.id);
                        setState(() => _opened = true);
                      },
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: const Text('Open letter'),
                    ),
                  ),
              ],
            ),
    );
  }
}
