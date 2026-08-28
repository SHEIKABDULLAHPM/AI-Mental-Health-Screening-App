package com.mindease.backend.coach.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Controlled long-term memory for the AI Coach.
 * Stores only useful, non-sensitive, user-relevant preferences and patterns.
 * Never stores passwords, journal content, screening answers, or sensitive data.
 */
@Document(collection = "coach_memories")
@CompoundIndex(name = "userId_category_idx", def = "{'userId': 1, 'category': 1}")
public class CoachMemory {

    @Id
    private String id;

    @Indexed
    private String userId;

    /** communication_style, coping_preference, wellness_goal, routine, preference */
    private String category;

    /** The stored memory content (short, factual) */
    private String content;

    /** How confident the system is in this memory */
    private Double confidence;

    /** Source conversationId that generated this memory */
    private String sourceConversationId;

    /** Whether the user has explicitly confirmed this memory */
    private boolean confirmed;

    /** Expiry for ephemeral memories */
    private Instant expiresAt;

    @Version
    private Long documentVersion;

    private Instant createdAt;
    private Instant updatedAt;

    public CoachMemory() {
    }

    private static final int MAX_CONTENT = 500;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }

    public String getContent() { return content; }
    public void setContent(String content) {
        this.content = content != null && content.length() > MAX_CONTENT
                ? content.substring(0, MAX_CONTENT) : content;
    }

    public Double getConfidence() { return confidence; }
    public void setConfidence(Double confidence) { this.confidence = confidence; }

    public String getSourceConversationId() { return sourceConversationId; }
    public void setSourceConversationId(String sourceConversationId) { this.sourceConversationId = sourceConversationId; }

    public boolean isConfirmed() { return confirmed; }
    public void setConfirmed(boolean confirmed) { this.confirmed = confirmed; }

    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
