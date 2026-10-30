import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/di/app_services.dart';
import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/shared/widgets/app_section_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Read-only history of the caller's stored assessments.
///
/// This screen talks to `GET /screenings/me` and renders exactly what the
/// backend stored. It deliberately does not recompute scores: clinical scoring
/// and the wellness profile remain server-owned.
class AssessmentHistoryScreen extends StatefulWidget {
  const AssessmentHistoryScreen({super.key});

  @override
  State<AssessmentHistoryScreen> createState() =>
      _AssessmentHistoryScreenState();
}

class _AssessmentHistoryScreenState extends State<AssessmentHistoryScreen> {
  bool _loading = true;
  bool _failed = false;
  List<MindeaseAssessmentSummary> _items = const [];
  Map<String, String> _titles = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final history = await mindeaseApi.assessmentHistory();
      var titles = <String, String>{};
      try {
        final catalog = await mindeaseApi.questionnaireCatalog();
        titles = {
          for (final questionnaire in catalog.questionnaires)
            questionnaire.code: questionnaire.title,
        };
      } on Object {
        // Titles are presentation only; the stored codes are still shown.
      }
      if (!mounted) return;
      setState(() {
        _items = history;
        _titles = titles;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Assessment history',
      body: _loading
          ? const LoadingView(message: 'Loading your assessments…')
          : _failed
              ? EmptyStateView(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unable to load assessments',
                  message: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              : _items.isEmpty
                  ? EmptyStateView(
                      icon: Icons.history_rounded,
                      title: 'No assessments yet',
                      message:
                          'Complete a screening and it will appear here with '
                          'its date and the sections you answered.',
                      actionLabel: 'Start screening',
                      onAction: () => context.push('/screening'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        children: [
                          Text(
                            '${_items.length} stored '
                            '${_items.length == 1 ? 'assessment' : 'assessments'}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          for (final item in _items) ...[
                            _AssessmentTile(
                              assessment: item,
                              titles: _titles,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          AppSectionCard(
                            icon: Icons.lock_outline_rounded,
                            title: 'Your records',
                            subtitle:
                                'Scores and insights are computed on the server '
                                'from these stored answers. Nothing on this '
                                'screen is recalculated in the app.',
                            children: const [],
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment, required this.titles});

  final MindeaseAssessmentSummary assessment;
  final Map<String, String> titles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = assessment.isCompleted;
    final recordedAt = assessment.recordedAt;
    final date = recordedAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(recordedAt.toLocal());
    final sections = assessment.questionnaireCodes.isEmpty
        ? 'No questionnaire sections recorded'
        : assessment.questionnaireCodes
            .map((code) => titles[code] ?? _fallbackTitle(code))
            .join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (completed
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                completed ? Icons.fact_check_rounded : Icons.pending_outlined,
                size: 20,
                color: completed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.tertiary,
              ),
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
                          date,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _StatusChip(completed: completed),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sections,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (!completed) ...[
                    const SizedBox(height: 6),
                    Text(
                      'This assessment was not submitted. You can start a new '
                      'screening from Check-in.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fallbackTitle(String code) {
    const known = {
      'phq9': 'PHQ-9',
      'gad7': 'GAD-7',
      'pss': 'PSS',
      'who5': 'WHO-5',
    };
    return known[code] ?? code.toUpperCase();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        completed ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        completed ? 'Completed' : 'In progress',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
