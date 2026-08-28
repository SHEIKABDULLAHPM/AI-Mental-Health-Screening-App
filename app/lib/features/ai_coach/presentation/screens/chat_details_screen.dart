import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/features/ai_coach/presentation/screens/chat_screen.dart';
import 'package:mindease/features/ai_coach/presentation/state/chat_controller.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Interactive view of a saved conversation — supports continuing the chat.
class ChatDetailsScreen extends StatefulWidget {
  const ChatDetailsScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ChatController>(context);

    if (controller.loading && controller.messages.isEmpty) {
      return const Scaffold(body: LoadingView());
    }

    final conversation = controller.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final title = conversation?.title ?? 'Conversation';

    return ChatScreen(
      title: title,
      conversationId: widget.conversationId,
    );
  }
}
