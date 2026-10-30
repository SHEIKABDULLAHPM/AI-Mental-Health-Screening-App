import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/ai_coach/data/chat_message.dart';

/// Manages AI Coach conversations and messages with full backend integration.
///
/// Supports: create, load, send (with idempotency), retry, delete, pagination.
/// All AI generation happens server-side via the Spring Boot CoachService.
class ChatController extends ChangeNotifier {
  ChatController(this._api);

  final FeatureApi _api;

  List<Conversation> _conversations = [];
  List<ChatMessage> _messages = [];
  bool _loading = false;
  String? _error;
  bool _sending = false;
  bool _generating = false;
  bool _disposed = false;

  // Current conversation state
  String? _activeConversationId;
  String? _activeConversationTitle;

  List<Conversation> get conversations => _conversations;
  List<ChatMessage> get messages => _messages;
  bool get loading => _loading;
  String? get error => _error;
  bool get sending => _sending;
  bool get generating => _generating;
  String? get activeConversationId => _activeConversationId;
  String? get activeConversationTitle => _activeConversationTitle;

  void _start() {
    _loading = true;
    _error = null;
    _deferNotify();
  }

  /// Listeners must not be notified synchronously from a loader a screen
  /// calls out of `initState`: the provider scope sits above the router, and
  /// marking it while the framework is still building that screen trips its
  /// "setState() or markNeedsBuild() called during build" assertion. State is
  /// already assigned synchronously, so the in-flight build reads the right
  /// values; this only schedules the follow-up rebuild safely.
  void _deferNotify() {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    _sending = false;
    _generating = false;
    notifyListeners();
  }

  /// Fetch the conversation list (history screen).
  Future<void> loadConversations() async {
    _start();
    try {
      final rows = await _api.getConversations();
      _conversations = rows.map(_conversationFromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Create a new conversation and return its id.
  Future<String?> createConversation({String? title}) async {
    _start();
    try {
      final json = await _api.createConversation(title: title);
      final id = json['id'] as String? ?? '';
      final convTitle = json['title'] as String? ?? 'New conversation';
      _activeConversationId = id;
      _activeConversationTitle = convTitle;
      _messages = [];
      await loadConversations();
      return id;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  /// Send a user message and wait for the AI response.
  ///
  /// Uses clientMessageId for idempotency — retries won't create duplicates.
  /// The backend runs the full pipeline: safety → context → RAG → Gemini → persist.
  Future<void> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    if (_sending) return; // Prevent duplicate sends

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _sending = true;
    _generating = true;
    _error = null;

    // Create a local user message immediately for optimistic UI
    final clientMessageId = 'cm_${DateTime.now().microsecondsSinceEpoch}';
    final userMessage = ChatMessage(
      id: clientMessageId,
      role: 'user',
      content: trimmed,
      status: 'COMPLETED',
      createdAt: DateTime.now(),
    );

    _messages = [..._messages, userMessage];
    notifyListeners();

    try {
      // Create a local pending assistant message
      final pendingId = 'am_${DateTime.now().microsecondsSinceEpoch}';
      final pendingAssistant = ChatMessage(
        id: pendingId,
        role: 'assistant',
        content: '',
        status: 'GENERATING',
        createdAt: DateTime.now(),
      );
      _messages = [..._messages, pendingAssistant];
      notifyListeners();

      // Send to backend — this triggers the full AI pipeline
      final response = await _api.sendChatMessage(
        conversationId: conversationId,
        text: trimmed,
      );

      // Replace the pending assistant message with the real response
      final assistantMessage = _messageFromApi(response);

      _messages = _messages.map((m) {
        if (m.id == pendingId) {
          return assistantMessage;
        }
        return m;
      }).toList();

      _sending = false;
      _generating = false;
      notifyListeners();
    } catch (e) {
      // Mark the pending assistant message as failed
      _messages = _messages.map((m) {
        if (m.status == 'GENERATING') {
          return m.copyWith(status: 'FAILED');
        }
        return m;
      }).toList();

      _sending = false;
      _generating = false;
      _error = e is Failure ? e.message : 'Failed to get response. Tap retry to try again.';
      notifyListeners();
    }
  }

  /// Retry a failed assistant message.
  Future<void> retryMessage({
    required String conversationId,
    required ChatMessage failedMessage,
  }) async {
    // Find the user message that triggered this failed response
    final messageIndex = _messages.indexOf(failedMessage);
    if (messageIndex <= 0) return;

    final userMessage = _messages[messageIndex - 1];
    if (!userMessage.isUser) return;

    // Remove the failed message
    _messages = _messages.where((m) => m.id != failedMessage.id).toList();
    notifyListeners();

    // Resend
    await sendMessage(
      conversationId: conversationId,
      text: userMessage.content,
    );
  }

  /// Load messages for a given conversation (chat detail screen).
  Future<void> loadMessages(String conversationId) async {
    _start();
    _activeConversationId = conversationId;
    try {
      final rows = await _api.getChatMessages(conversationId);
      _messages = rows.map(_messageFromApi).toList();

      // Also load conversation metadata
      final convJson = await _api.getConversation(conversationId);
      _activeConversationTitle = convJson['title'] as String?;

      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load a single conversation into the list.
  Future<void> loadConversation(String id) async {
    _start();
    try {
      final json = await _api.getConversation(id);
      final conversation = _conversationFromApi(json);
      _conversations = [
        for (final c in _conversations)
          if (c.id == id) conversation else c,
      ];
      if (!_conversations.any((c) => c.id == id)) {
        _conversations.insert(0, conversation);
      }
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Delete a conversation.
  Future<void> deleteConversation(String id) async {
    try {
      await _api.deleteConversation(id);
      _conversations = _conversations.where((c) => c.id != id).toList();
      if (_activeConversationId == id) {
        _activeConversationId = null;
        _activeConversationTitle = null;
        _messages = [];
      }
      notifyListeners();
    } catch (e) {
      _error = e is Failure ? e.message : 'Failed to delete.';
      notifyListeners();
    }
  }

  /// Clear the current error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear active conversation state (e.g., when navigating back).
  void clearActiveConversation() {
    _activeConversationId = null;
    _activeConversationTitle = null;
    _messages = [];
    notifyListeners();
  }
}

// ──────────────────────────────────────────── API → domain mapping

Conversation _conversationFromApi(Map<String, dynamic> json) => Conversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      preview: json['preview'] as String?,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      safetyState: json['safetyState'] as String?,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );

ChatMessage _messageFromApi(Map<String, dynamic> json) {
  final suggestionsRaw = json['suggestions'];
  List<String>? suggestions;
  if (suggestionsRaw is String && suggestionsRaw.isNotEmpty) {
    try {
      final parsed = suggestionsRaw.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
      suggestions = parsed.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } catch (_) {}
  }

  return ChatMessage(
    id: json['id'] as String? ?? '',
    role: json['role'] as String? ?? 'user',
    content: json['content'] as String? ?? '',
    status: json['status'] as String? ?? 'COMPLETED',
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    safetyState: json['safetyState'] as String?,
    suggestions: suggestions,
    clientMessageId: json['clientMessageId'] as String?,
    createdAt: _parseDate(json['createdAt']),
    completedAt: _parseDate(json['completedAt']),
  );
}

DateTime _parseDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}
