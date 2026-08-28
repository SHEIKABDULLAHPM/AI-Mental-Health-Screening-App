/// A single chat message in an AI Coach conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.status = 'COMPLETED',
    this.sequence = 0,
    this.safetyState,
    this.suggestions,
    this.clientMessageId,
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final String status; // PENDING, GENERATING, COMPLETED, FAILED
  final int sequence;
  final String? safetyState;
  final List<String>? suggestions;
  final String? clientMessageId;
  final DateTime? createdAt;
  final DateTime? completedAt;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isGenerating => status == 'GENERATING';
  bool get isFailed => status == 'FAILED';
  bool get isCrisis =>
      safetyState == 'HIGH_RISK' || safetyState == 'IMMEDIATE_DANGER';

  ChatMessage copyWith({
    String? content,
    String? status,
    String? safetyState,
    List<String>? suggestions,
    DateTime? completedAt,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      status: status ?? this.status,
      sequence: sequence,
      safetyState: safetyState ?? this.safetyState,
      suggestions: suggestions ?? this.suggestions,
      clientMessageId: clientMessageId,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// A saved conversation metadata item.
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    this.preview,
    this.messageCount = 0,
    this.safetyState,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? preview;
  final int messageCount;
  final String? safetyState;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
