import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/future_letters/data/future_letter.dart';
import 'package:mindease/shared/widgets/app_progress_bar.dart';

/// Card for one future letter with its delivery status.
class FutureLetterCard extends StatelessWidget {
  const FutureLetterCard({
    super.key,
    required this.letter,
    this.onTap,
  });

  final FutureLetter letter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = letter.status;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  Icons.mail_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      letter.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status == LetterStatus.scheduled
                          ? 'Arrives ${DateFormat.yMMMd().format(letter.scheduledDate)}'
                          : 'For ${letter.recipient} · '
                              '${DateFormat.yMMMd().format(letter.scheduledDate)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: status.label,
                color: status == LetterStatus.scheduled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
