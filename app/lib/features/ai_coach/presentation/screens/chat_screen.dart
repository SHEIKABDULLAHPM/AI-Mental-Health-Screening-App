import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/ai_coach/data/chat_message.dart';
import 'package:mindease/features/ai_coach/presentation/state/chat_controller.dart';
import 'package:mindease/features/ai_coach/presentation/widgets/chat_widgets.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// AI Coach chat screen with real backend AI responses, streaming states,
/// retry support, and dynamic suggestions.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.title = 'AI Coach',
    this.initialPrompt,
    this.conversationId,
  });

  final String title;
  final String? initialPrompt;
  final String? conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;

    if (widget.initialPrompt != null) {
      _input.text = widget.initialPrompt!;
    }

    // Load messages if we have an existing conversation
    if (_conversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Provider.of<ChatController>(context, listen: false)
            .loadMessages(_conversationId!);
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final controller = Provider.of<ChatController>(context, listen: false);
    if (controller.sending) return;

    _input.clear();
    _scrollToEnd();

    // Create conversation if needed
    if (_conversationId == null) {
      final id = await controller.createConversation();
      if (id == null || !mounted) return;
      _conversationId = id;
    }

    await controller.sendMessage(
      conversationId: _conversationId!,
      text: trimmed,
    );

    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ChatController>(context);
    final messages = controller.messages;
    final hasCrisis = messages.any((m) => m.isCrisis);

    return FeatureScaffold(
      title: widget.title,
      actions: [
        if (_conversationId != null)
          IconButton(
            tooltip: 'Delete conversation',
            onPressed: () => _confirmDelete(controller),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
      body: Column(
        children: [
          // Context memory indicator
          const SizedBox(height: AppSpacing.xs),
          const Center(child: ContextMemoryChip()),
          const SizedBox(height: AppSpacing.xs),

          // Error banner
          if (controller.error != null)
            _ErrorBanner(
              message: controller.error!,
              onDismiss: controller.clearError,
            ),

          // Messages
          Expanded(
            child: messages.isEmpty && !controller.loading
                ? _EmptyCoachState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Column(
                        children: [
                          ChatBubble(
                            message: message,
                            onRetry: message.isFailed
                                ? () => _retryMessage(controller, message)
                                : null,
                          ),
                          // Show suggestions after assistant messages
                          if (message.isAssistant &&
                              message.suggestions != null &&
                              message.suggestions!.isNotEmpty &&
                              !controller.generating)
                            _SuggestionChips(
                              suggestions: message.suggestions!,
                              onSelected: (s) => _send(s),
                            ),
                        ],
                      );
                    },
                  ),
          ),

          // Crisis support card
          if (hasCrisis) const CrisisSupportCard(),

          // Input area
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !controller.sending,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: controller.sending ? null : _send,
                      decoration: InputDecoration(
                        hintText: controller.sending
                            ? 'Waiting for response…'
                            : 'Message your coach…',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                    ),
                    onPressed: controller.sending
                        ? null
                        : () => _send(_input.text),
                    icon: controller.generating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _retryMessage(ChatController controller, ChatMessage failedMessage) {
    if (_conversationId != null) {
      controller.retryMessage(
        conversationId: _conversationId!,
        failedMessage: failedMessage,
      );
    }
  }

  Future<void> _confirmDelete(ChatController controller) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation'),
        content: const Text(
          'This conversation will be permanently deleted. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && mounted && _conversationId != null) {
      await controller.deleteConversation(_conversationId!);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

/// Empty state when no messages exist yet.
class _EmptyCoachState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 38,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Your AI Coach',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'I am here to listen and support you. Share what is on your mind — everything you say is private.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Error banner with dismiss.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Suggestion chips shown after assistant messages.
class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({
    required this.suggestions,
    required this.onSelected,
  });

  final List<String> suggestions;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final suggestion in suggestions.take(3))
            ActionChip(
              label: Text(
                suggestion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              avatar: const Icon(Icons.arrow_forward_rounded, size: 14),
              onPressed: () => onSelected(suggestion),
            ),
        ],
      ),
    );
  }
}
