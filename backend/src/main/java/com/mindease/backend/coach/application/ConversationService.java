package com.mindease.backend.coach.application;

import java.time.Instant;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.coach.domain.Conversation;
import com.mindease.backend.coach.domain.ConversationRepository;
import com.mindease.backend.coach.domain.Message;
import com.mindease.backend.coach.domain.MessageRepository;
import com.mindease.backend.coach.dto.ConversationResponse;
import com.mindease.backend.coach.dto.CreateConversationRequest;
import com.mindease.backend.coach.dto.MessageResponse;
import com.mindease.backend.coach.dto.SendMessageRequest;

@Service
public class ConversationService {

    private static final Logger log = LoggerFactory.getLogger(ConversationService.class);
    private static final int MAX_PAGE_SIZE = 50;
    private static final int DEFAULT_HISTORY_LIMIT = 100;

    private final ConversationRepository conversationRepo;
    private final MessageRepository messageRepo;

    public ConversationService(ConversationRepository conversationRepo, MessageRepository messageRepo) {
        this.conversationRepo = conversationRepo;
        this.messageRepo = messageRepo;
    }

    // ── Conversation CRUD ──

    public ConversationResponse createConversation(String userId, CreateConversationRequest request) {
        Conversation c = new Conversation();
        c.setUserId(userId);
        c.setTitle(request.title() != null ? request.title() : "New conversation");
        c.setMessageCount(0);
        c.setSafetyState("NORMAL");
        c.setCreatedAt(Instant.now());
        c.setUpdatedAt(Instant.now());
        Conversation saved = conversationRepo.save(c);
        log.info("conversation_created userId={} conversationId={}", userId, saved.getId());
        return ConversationResponse.from(saved);
    }

    public List<ConversationResponse> getConversations(String userId, int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), MAX_PAGE_SIZE);
        List<Conversation> conversations = conversationRepo.findByUserIdOrderByUpdatedAtDesc(
                userId, PageRequest.of(safePage, safeSize));
        return conversations.stream().map(ConversationResponse::from).toList();
    }

    public ConversationResponse getConversation(String userId, String conversationId) {
        Conversation c = conversationRepo.findByIdAndUserId(conversationId, userId)
                .orElseThrow(() -> ApiException.notFound("Conversation not found"));
        return ConversationResponse.from(c);
    }

    public void deleteConversation(String userId, String conversationId) {
        Conversation c = conversationRepo.findByIdAndUserId(conversationId, userId)
                .orElseThrow(() -> ApiException.notFound("Conversation not found"));
        messageRepo.deleteByConversationIdAndUserId(conversationId, userId);
        conversationRepo.deleteById(c.getId());
        log.info("conversation_deleted userId={} conversationId={}", userId, conversationId);
    }

    // ── Message CRUD ──

    public List<MessageResponse> getMessages(String userId, String conversationId) {
        // Verify ownership
        conversationRepo.findByIdAndUserId(conversationId, userId)
                .orElseThrow(() -> ApiException.notFound("Conversation not found"));

        List<Message> messages = messageRepo.findByConversationIdAndUserIdOrderBySequenceAsc(
                conversationId, userId, PageRequest.of(0, DEFAULT_HISTORY_LIMIT));
        return messages.stream().map(MessageResponse::from).toList();
    }

    /**
     * Store a user message. Returns the saved message.
     * Does NOT generate an AI response — that is the CoachService's job.
     */
    public Message storeUserMessage(String userId, String conversationId, SendMessageRequest request) {
        // Idempotency check
        if (request.clientMessageId() != null && !request.clientMessageId().isBlank()) {
            var existing = messageRepo.findByClientMessageIdAndUserId(request.clientMessageId(), userId);
            if (existing.isPresent()) {
                return existing.get(); // Already processed
            }
        }

        // Verify ownership
        Conversation conversation = conversationRepo.findByIdAndUserId(conversationId, userId)
                .orElseThrow(() -> ApiException.notFound("Conversation not found"));

        // Determine sequence
        var lastMessage = messageRepo.findTopByConversationIdAndUserIdOrderBySequenceDesc(
                conversationId, userId);
        int nextSequence = lastMessage.map(m -> m.getSequence() + 1).orElse(1);

        // Create and save user message
        Message msg = new Message();
        msg.setUserId(userId);
        msg.setConversationId(conversationId);
        msg.setRole("user");
        msg.setContent(request.message());
        msg.setStatus("COMPLETED");
        msg.setSequence(nextSequence);
        msg.setClientMessageId(request.clientMessageId());
        msg.setCreatedAt(Instant.now());
        msg.setCompletedAt(Instant.now());
        Message saved = messageRepo.save(msg);

        // Update conversation metadata
        conversation.setMessageCount(nextSequence);
        conversation.setLastMessagePreview(request.message());
        conversation.setUpdatedAt(Instant.now());
        conversationRepo.save(conversation);

        return saved;
    }

    /**
     * Store a pending assistant message (before AI generation).
     */
    public Message createPendingAssistantMessage(String userId, String conversationId, String clientMessageId) {
        var lastMessage = messageRepo.findTopByConversationIdAndUserIdOrderBySequenceDesc(
                conversationId, userId);
        int nextSequence = lastMessage.map(m -> m.getSequence() + 1).orElse(1);

        Message msg = new Message();
        msg.setUserId(userId);
        msg.setConversationId(conversationId);
        msg.setRole("assistant");
        msg.setContent("");
        msg.setStatus("GENERATING");
        msg.setSequence(nextSequence);
        msg.setClientMessageId(clientMessageId);
        msg.setCreatedAt(Instant.now());
        return messageRepo.save(msg);
    }

    /**
     * Complete an assistant message with the AI response.
     */
    public Message completeAssistantMessage(Message msg, String content, String safetyState,
            String suggestions, String model, String promptVersion) {
        msg.setContent(content);
        msg.setStatus("COMPLETED");
        msg.setSafetyState(safetyState);
        msg.setSuggestions(suggestions);
        msg.setModel(model);
        msg.setPromptVersion(promptVersion);
        msg.setCompletedAt(Instant.now());
        Message saved = messageRepo.save(msg);

        // Update conversation
        conversationRepo.findByIdAndUserId(msg.getConversationId(), msg.getUserId())
                .ifPresent(c -> {
                    c.setLastMessagePreview(content);
                    c.setUpdatedAt(Instant.now());
                    if (!"NORMAL".equals(safetyState)) {
                        c.setSafetyState(safetyState);
                    }
                    conversationRepo.save(c);
                });

        return saved;
    }

    /**
     * Mark an assistant message as failed.
     */
    public Message failAssistantMessage(Message msg) {
        msg.setStatus("FAILED");
        msg.setCompletedAt(Instant.now());
        return messageRepo.save(msg);
    }
}
