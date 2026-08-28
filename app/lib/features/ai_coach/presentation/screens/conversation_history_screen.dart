import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/ai_coach/presentation/state/chat_controller.dart';
import 'package:mindease/features/ai_coach/presentation/widgets/chat_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Saved AI Coach conversations with delete support.
class ConversationHistoryScreen extends StatefulWidget {
  const ConversationHistoryScreen({super.key});

  @override
  State<ConversationHistoryScreen> createState() =>
      _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState extends State<ConversationHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatController>(context, listen: false).loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ChatController>(context);
    final conversations = controller.conversations;
    return FeatureScaffold(
      title: 'Conversations',
      body: controller.loading && conversations.isEmpty
          ? const LoadingView()
          : conversations.isEmpty
              ? const EmptyStateView(
                  icon: Icons.history_rounded,
                  title: 'No conversations yet',
                  message: 'Your past chats with your AI coach appear here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    SectionHeader(
                      title: '${conversations.length} conversations',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...conversations.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Dismissible(
                          key: ValueKey(c.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete conversation'),
                                content: const Text(
                                  'This conversation will be permanently deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (_) {
                            controller.deleteConversation(c.id);
                          },
                          child: ConversationTile(
                            conversation: c,
                            onTap: () =>
                                context.push('/ai-coach/${c.id}'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
