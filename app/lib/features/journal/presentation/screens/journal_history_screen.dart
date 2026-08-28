import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/journal/data/journal_entry.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/features/journal/presentation/widgets/journal_entry_card.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Full journal history with type filter and search.
class JournalHistoryScreen extends StatefulWidget {
  const JournalHistoryScreen({super.key});

  @override
  State<JournalHistoryScreen> createState() => _JournalHistoryScreenState();
}

class _JournalHistoryScreenState extends State<JournalHistoryScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  JournalEntryType? _filter;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final controller = context.read<JournalController>();
    _search.text = controller.searchQuery;
    _filter = JournalEntryType.values
        .where(
          (type) => type.name == controller.typeFilter,
        )
        .firstOrNull;
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _search.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final controller = Provider.of<JournalController>(context, listen: false);
      controller.loadMore();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        final controller =
            Provider.of<JournalController>(context, listen: false);
        controller.search(query);
      }
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final controller = Provider.of<JournalController>(context, listen: false);
    await controller.loadEntries(reset: true);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    setState(() {});
    context.read<JournalController>().search('');
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<JournalController>(context);
    final entries = controller.entries;
    final loading = controller.loading;

    return FeatureScaffold(
      title: 'Journal History',
      body: loading && entries.isEmpty
          ? const LoadingView()
          : controller.error != null && entries.isEmpty
              ? ErrorStateView(
                  title: 'Couldn’t load your journal',
                  message: controller.error!,
                  onRetry: _load,
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        0,
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _search,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search entries…',
                              prefixIcon:
                                  const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 20,
                                      ),
                                      onPressed: _clearSearch,
                                    ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _filterChip('All', null),
                                _filterChip('Text', JournalEntryType.text),
                                _filterChip('Voice', JournalEntryType.voice),
                                _filterChip('Image', JournalEntryType.image),
                                _filterChip('Video', JournalEntryType.video),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: entries.isEmpty
                          ? EmptyStateView(
                              icon: Icons.auto_stories_outlined,
                              title: 'No entries here',
                              message: _search.text.isEmpty && _filter == null
                                  ? 'Write your first reflection to get started.'
                                  : 'Try a different filter or search term.',
                              actionLabel: 'Create entry',
                              onAction: () => context.push('/journal-create'),
                            )
                          : RefreshIndicator(
                              onRefresh: () => controller.refreshEntries(),
                              child: ListView(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                children: [
                                  Text(
                                    '${controller.totalCount} ${controller.totalCount == 1 ? 'entry' : 'entries'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  ...entries.map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.sm,
                                      ),
                                      child: JournalEntryCard(
                                        entry: e,
                                        onTap: () =>
                                            context.push('/journal/${e.id}'),
                                      ),
                                    ),
                                  ),
                                  if (controller.hasMore)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: AppSpacing.md,
                                      ),
                                      child: Center(
                                        child: loading
                                            ? const CircularProgressIndicator()
                                            : TextButton(
                                                onPressed: () =>
                                                    controller.loadMore(),
                                                child: const Text('Load more'),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _filterChip(String label, JournalEntryType? type) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (isSelected) {
          setState(() => _filter = isSelected ? type : null);
          final controller =
              Provider.of<JournalController>(context, listen: false);
          controller.filterByType(isSelected ? type?.name : null);
        },
      ),
    );
  }
}
