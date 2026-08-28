import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/features/journal/presentation/widgets/journal_entry_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// The Journal landing screen: a private writing space and recent entries.
class JournalHomeScreen extends StatefulWidget {
  const JournalHomeScreen({super.key});

  @override
  State<JournalHomeScreen> createState() => _JournalHomeScreenState();
}

class _JournalHomeScreenState extends State<JournalHomeScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels <
            _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    context.read<JournalController>().loadMore();
  }

  Future<void> _load() =>
      context.read<JournalController>().loadEntries(reset: true);

  void _onSearchChanged(String query) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) context.read<JournalController>().search(query);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    setState(() {});
    context.read<JournalController>().search('');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<JournalController>();
    final entries = controller.entries;
    final isSearching = _search.text.trim().isNotEmpty;

    return FeatureScaffold(
      title: 'Journal',
      actions: [
        IconButton(
          tooltip: 'View journal history',
          onPressed: () => context.push('/journal-history'),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
      body: controller.loading && entries.isEmpty
          ? const LoadingView(message: 'Loading your entries…')
          : controller.error != null && entries.isEmpty
              ? ErrorStateView(
                  title: 'Couldn’t load your journal',
                  message: controller.error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: controller.refreshEntries,
                  child: ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      _JournalWelcomeCard(entryCount: controller.totalCount),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _search,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search your entries',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: isSearching
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  icon:
                                      const Icon(Icons.close_rounded, size: 20),
                                  onPressed: _clearSearch,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeader(
                        title:
                            isSearching ? 'Search results' : 'Recent entries',
                        actionLabel: entries.isEmpty ? null : 'View all',
                        onAction: entries.isEmpty
                            ? null
                            : () => context.push('/journal-history'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (entries.isEmpty)
                        EmptyStateView(
                          icon: isSearching
                              ? Icons.search_off_rounded
                              : Icons.auto_stories_outlined,
                          title: isSearching
                              ? 'No entries found'
                              : 'Your journal is ready',
                          message: isSearching
                              ? 'Nothing matches “${_search.text.trim()}”. Try another word.'
                              : 'Capture a thought, a voice note, or a moment when it feels right.',
                          actionLabel: isSearching ? null : 'Write an entry',
                          onAction: isSearching
                              ? null
                              : () => context.push('/journal-create'),
                        )
                      else ...[
                        ...entries.map(
                          (entry) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: JournalEntryCard(
                              entry: entry,
                              onTap: () => context.push('/journal/${entry.id}'),
                            ),
                          ),
                        ),
                        if (controller.hasMore)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Center(
                              child: controller.loading
                                  ? const CircularProgressIndicator()
                                  : TextButton.icon(
                                      onPressed: controller.loadMore,
                                      icon:
                                          const Icon(Icons.expand_more_rounded),
                                      label: const Text('Load more entries'),
                                    ),
                            ),
                          )
                        else if (controller.totalCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Text(
                              'You’re all caught up',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
      bottomBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: FilledButton.icon(
            onPressed: () => context.push('/journal-create'),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('New entry'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalWelcomeCard extends StatelessWidget {
  const _JournalWelcomeCard({required this.entryCount});

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEntries = entryCount > 0;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasEntries
                        ? 'A moment for yourself'
                        : 'A space that’s yours',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    hasEntries
                        ? '$entryCount ${entryCount == 1 ? 'entry' : 'entries'} safely collected here.'
                        : 'Write freely, record a thought, or save a meaningful photo.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
