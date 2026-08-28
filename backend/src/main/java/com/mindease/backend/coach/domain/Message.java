package com.mindease.backend.coach.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A single message within a coach conversation.
 * User messages and AI assistant messages are both stored here.
 */
@Document(collection = "coach_messages")
@CompoundIndex(name = "conversationId_createdAt_idx", def = "{'conversationId': 1, 'createdAt': 1}")
@CompoundIndex(name = "userId_conversationId_idx", def = "{'userId': 1, 'conversationId': 1}")
public class Message {

    @Id
    private String id;

    @Indexed
    private String userId;

    @Indexed
    private String conversationId;

    /** user or assistant */
    private String role;

    /** The message content (max bounded) */
    private String content;

    /** PENDING, GENERATING, COMPLETED, FAILED */
    private String status;

    /** Monotonically increasing sequence within the conversation */
    private int sequence;

    /** Client-generated idempotency key to prevent duplicate messages */
    private String clientMessageId;

    /** AI metadata */
    private String model;
    private String promptVersion;
    private String contextVersion;
    private String safetyPolicyVersion;

    /** Safety state for assistant messages */
    private String safetyState;

    /** Suggestions generated with this response (JSON array, nullable) */
    private String suggestions;

    @Version
    private Long documentVersion;

    private Instant createdAt;
    private Instant completedAt;

    public Message() {
    }

    private static final int MAX_CONTENT = 10000;
    private static final int MAX_SUGGESTIONS = 2000;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getConversationId() { return conversationId; }
    public void setConversationId(String conversationId) { this.conversationId = conversationId; }

    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }

    public String getContent() { return content; }
    public void setContent(String content) {
        this.content = content != null && content.length() > MAX_CONTENT
                ? content.substring(0, MAX_CONTENT) : content;
    }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public int getSequence() { return sequence; }
    public void setSequence(int sequence) { this.sequence = sequence; }

    public String getClientMessageId() { return clientMessageId; }
    public void setClientMessageId(String clientMessageId) { this.clientMessageId = clientMessageId; }

    public String getModel() { return model; }
    public void setModel(String model) { this.model = model; }

    public String getPromptVersion() { return promptVersion; }
    public void setPromptVersion(String promptVersion) { this.promptVersion = promptVersion; }

    public String getContextVersion() { return contextVersion; }
    public void setContextVersion(String contextVersion) { this.contextVersion = contextVersion; }

    public String getSafetyPolicyVersion() { return safetyPolicyVersion; }
    public void setSafetyPolicyVersion(String safetyPolicyVersion) { this.safetyPolicyVersion = safetyPolicyVersion; }

    public String getSafetyState() { return safetyState; }
    public void setSafetyState(String safetyState) { this.safetyState = safetyState; }

    public String getSuggestions() { return suggestions; }
    public void setSuggestions(String suggestions) {
        this.suggestions = suggestions != null && suggestions.length() > MAX_SUGGESTIONS
                ? suggestions.substring(0, MAX_SUGGESTIONS) : suggestions;
    }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getCompletedAt() { return completedAt; }
    public void setCompletedAt(Instant completedAt) { this.completedAt = completedAt; }
}
