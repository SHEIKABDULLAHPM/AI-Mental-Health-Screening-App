import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/journal/data/journal_entry.dart';

/// Compact, accessible summary of a journal entry used in lists.
class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.highlight = false,
  });

  final JournalEntry entry;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColor(theme, entry.type);
    final supportingText = entry.content.trim().isNotEmpty
        ? entry.content.trim()
        : entry.type == JournalEntryType.voice
            ? 'Voice recording${entry.audioDurationLabel.isEmpty ? '' : ' · ${entry.audioDurationLabel}'}'
            : 'Photo entry';

    return Card(
      color: highlight ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_typeIcon(entry.type), size: 20, color: typeColor),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.type.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: typeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (entry.emotion != null)
                          _EmotionLabel(label: entry.emotion!)
                        else if (entry.aiAnalysis?.isProcessing == true)
                          Icon(
                            Icons.hourglass_top_rounded,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          )
                        else if (entry.aiAnalysis?.isReady == true)
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      supportingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      entry.dateLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _typeIcon(JournalEntryType type) => switch (type) {
        JournalEntryType.text => Icons.notes_rounded,
        JournalEntryType.voice => Icons.mic_rounded,
        JournalEntryType.image => Icons.photo_rounded,
        JournalEntryType.video => Icons.videocam_rounded,
      };

  static Color _typeColor(ThemeData theme, JournalEntryType type) =>
      switch (type) {
        JournalEntryType.text => theme.colorScheme.primary,
        JournalEntryType.voice => theme.colorScheme.tertiary,
        JournalEntryType.image => theme.colorScheme.secondary,
        JournalEntryType.video => theme.colorScheme.error,
      };
}

class _EmotionLabel extends StatelessWidget {
  const _EmotionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
