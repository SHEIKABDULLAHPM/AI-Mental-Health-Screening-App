import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/recommendations/data/recommendation.dart';
import 'package:mindease/features/recommendations/presentation/state/recommendation_controller.dart';
import 'package:mindease/shared/widgets/ai_insight_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Details of a single recommendation with feedback and content navigation.
class RecommendationDetailsScreen extends StatefulWidget {
  const RecommendationDetailsScreen({super.key, required this.recommendationId});

  final String recommendationId;

  @override
  State<RecommendationDetailsScreen> createState() =>
      _RecommendationDetailsScreenState();
}

class _RecommendationDetailsScreenState
    extends State<RecommendationDetailsScreen> {
  String? _selectedFeedback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final ctrl = context.read<RecommendationController>();
        ctrl.loadById(widget.recommendationId);
        // Record SHOWN interaction
        ctrl.recordInteraction(widget.recommendationId, 'SHOWN');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = context.watch<RecommendationController>();
    final item = ctrl.currentRecommendation;

    return FeatureScaffold(
      title: 'Recommendation',
      body: ctrl.loading || item == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                // ── Category icon banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.primary.withValues(alpha: 0.25),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: Icon(
                    parseCategory(item.category).icon,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Category label
                Text(
                  parseCategory(item.category).label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),

                // ── Title
                Text(
                  item.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Meta chips: duration, difficulty
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    if (item.duration != null)
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        text: item.duration!,
                      ),
                    if (item.difficulty != null)
                      _MetaChip(
                        icon: Icons.signal_cellular_alt_rounded,
                        text: item.difficulty!,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Description
                Text(
                  item.description,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),

                // ── "Why this?" personalized explanation
                if (item.reason != null && item.reason!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AIInsightCard(
                    title: 'Why this is recommended',
                    text: item.reason!,
                    icon: Icons.lightbulb_outline_rounded,
                    iconColor: theme.colorScheme.primary,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),

                // ── Start action
                FilledButton.icon(
                  onPressed: () => _startActivity(context, item),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Start activity'),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Feedback section
                _FeedbackSection(
                  selectedFeedback: _selectedFeedback,
                  onFeedback: (type) => _submitFeedback(context, item, type),
                ),
              ],
            ),
    );
  }

  void _startActivity(BuildContext context, Recommendation item) {
    final ref = item.contentReference;
    if (ref == null || ref.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This activity is not available yet.')),
      );
      return;
    }

    // Record STARTED interaction
    context.read<RecommendationController>().recordInteraction(
          widget.recommendationId,
          'STARTED',
        );

    // Smart routing: map recommendation category to the correct feature
    final route = _resolveRoute(ref, item.category);
    context.push(route);
  }

  /// Resolve the navigation route based on the recommendation's content
  /// reference and category. Maps to real feature screens instead of
  /// generic activity paths.
  String _resolveRoute(String contentRef, String category) {
    // Direct routes that already exist in the router
    if (contentRef == '/mood-checkin') return '/mood-record';
    if (contentRef == '/journal-prompt') return '/journal-create';
    if (contentRef.startsWith('/relax/')) return contentRef;
    if (contentRef.startsWith('/mood')) return '/mood-record';
    if (contentRef.startsWith('/journal')) return '/journal-create';

    // Category-based routing for /activities/* paths
    final slug = contentRef.replaceFirst('/activities/', '');
    switch (category) {
      case 'exercises':
      case 'meditation':
        // Breathing, PMR, walking, body scan → Relax feature
        return '/relax';
      case 'sounds':
        // Soundscapes, sleep sounds → Relax feature
        return '/relax';
      case 'articles':
        // Journaling prompts, reflection → Journal create
        return '/journal-create';
      case 'personalized':
        // Mood check-in, awareness → Mood record
        return '/mood-record';
      default:
        // Fallback: try the activity player for unknown paths
        return '/activities/$slug';
    }
  }

  void _submitFeedback(
    BuildContext context,
    Recommendation item,
    String type,
  ) {
    setState(() => _selectedFeedback = type);
    context.read<RecommendationController>().recordFeedback(item.id, type);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback!')),
      );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(text),
      labelStyle: theme.textTheme.labelMedium,
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({this.selectedFeedback, this.onFeedback});

  final String? selectedFeedback;
  final ValueChanged<String>? onFeedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Was this helpful?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _FeedbackChip(
              label: 'Helpful',
              icon: Icons.thumb_up_outlined,
              selected: selectedFeedback == 'HELPFUL',
              onTap: () => onFeedback?.call('HELPFUL'),
            ),
            _FeedbackChip(
              label: 'Not useful',
              icon: Icons.thumb_down_outlined,
              selected: selectedFeedback == 'NOT_USEFUL',
              onTap: () => onFeedback?.call('NOT_USEFUL'),
            ),
            _FeedbackChip(
              label: 'Already did this',
              icon: Icons.check_circle_outline,
              selected: selectedFeedback == 'ALREADY_COMPLETED',
              onTap: () => onFeedback?.call('ALREADY_COMPLETED'),
            ),
            _FeedbackChip(
              label: 'Dismiss',
              icon: Icons.close,
              selected: selectedFeedback == 'DISMISSED',
              onTap: () => onFeedback?.call('DISMISSED'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  const _FeedbackChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      avatar: Icon(icon, size: 16),
      selected: selected,
      onSelected: onTap != null ? (_) => onTap!() : null,
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.primary,
    );
  }
}
