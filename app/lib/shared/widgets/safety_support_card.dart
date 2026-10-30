import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_colors.dart';
import 'package:mindease/core/theme/app_spacing.dart';

/// Explicit support surface unlocked by a positive PHQ-9 item-9 screen.
///
/// Shown regardless of the AI job state - a safety answer must never wait on
/// an LLM. Copy avoids diagnosis and points to real human support.
class SafetySupportCard extends StatelessWidget {
  const SafetySupportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volunteer_activism_rounded,
                color: AppColors.error,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You deserve support right now',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'One of your answers mentioned thoughts of self-harm. This is not '
            'a diagnosis, but please do not carry it alone. Reach out to '
            'someone you trust today, and if you are in immediate danger '
            'contact your local emergency number or a crisis service now.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
