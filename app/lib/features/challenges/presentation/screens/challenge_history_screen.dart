import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/challenges/presentation/state/challenge_controller.dart';
import 'package:mindease/features/challenges/presentation/widgets/challenge_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Paginated list of completed and expired challenges.
class ChallengeHistoryScreen extends StatefulWidget {
  const ChallengeHistoryScreen({super.key});

  @override
  State<ChallengeHistoryScreen> createState() => _ChallengeHistoryScreenState();
}

class _ChallengeHistoryScreenState extends State<ChallengeHistoryScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<ChallengeController>();
    ctrl.loadHistory(refresh: true);
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      context.read<ChallengeController>().loadHistory();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ChallengeController>();
    final history = ctrl.history;

    return FeatureScaffold(
      title: 'Challenge History',
      body: ctrl.historyLoading && history.isEmpty
          ? const LoadingView()
          : history.isEmpty
              ? const EmptyStateView(
                  icon: Icons.history_rounded,
                  title: 'No history yet',
                  message:
                      'Completed and expired challenges will appear here.',
                )
              : RefreshIndicator(
                  onRefresh: () => ctrl.loadHistory(refresh: true),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    itemCount: history.length + (ctrl.historyHasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= history.length) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final c = history[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ChallengeCard(
                          challenge: c,
                          onTap: () =>
                              context.push('/challenges/${c.id}'),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
