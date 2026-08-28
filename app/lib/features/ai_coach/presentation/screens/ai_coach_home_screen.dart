import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/ai_coach/presentation/state/chat_controller.dart';
import 'package:mindease/features/ai_coach/presentation/widgets/chat_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/section_header.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// AI Coach home: dynamic greeting, new chat, and saved conversations.
class AiCoachHomeScreen extends StatefulWidget {
  const AiCoachHomeScreen({super.key});

  @override
  State<AiCoachHomeScreen> createState() => _AiCoachHomeScreenState();
}

class _AiCoachHomeScreenState extends State<AiCoachHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatController>(context, listen: false).loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Provider.of<ChatController>(context);
    final conversations = controller.conversations;

    return FeatureScaffold(
      title: 'AI Coach',
      actions: [
        IconButton(
          tooltip: 'Conversation history',
          onPressed: () => context.push('/ai-coach-history'),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
      body: controller.loading && conversations.isEmpty
          ? const LoadingView()
          : FeatureBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome card
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How can I help?',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'I am your AI wellness companion. I remember our '
                            'conversations and offer personalised guidance '
                            'based on your context.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => context.push('/ai-coach-chat'),
                              icon: const Icon(
                                Icons.chat_bubble_rounded,
                                size: 18,
                              ),
                              label: const Text('Start a chat'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Recent conversations
                  SectionHeader(
                    title: 'Recent conversations',
                    actionLabel: conversations.isNotEmpty ? 'See all' : null,
                    onAction: conversations.isNotEmpty
                        ? () => context.push('/ai-coach-history')
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (conversations.isEmpty)
                    const EmptyStateView(
                      icon: Icons.smart_toy_outlined,
                      title: 'No conversations yet',
                      message:
                          'Start a chat and your history will appear here.',
                    )
                  else
                    ...conversations.take(5).map(
                          (c) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: ConversationTile(
                              conversation: c,
                              onTap: () =>
                                  context.push('/ai-coach/${c.id}'),
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}
