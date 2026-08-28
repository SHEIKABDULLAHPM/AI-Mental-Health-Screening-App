package com.mindease.backend.features.recommendations.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Tracks user interactions with recommendations.
 * Used for feedback, repetition control, and ranking improvement.
 */
@Document(collection = "recommendation_interactions")
@CompoundIndexes({
    @CompoundIndex(name = "userId_contentId_type_idx", def = "{'userId': 1, 'contentId': 1, 'interactionType': 1}"),
    @CompoundIndex(name = "userId_createdAt_idx", def = "{'userId': 1, 'createdAt': -1}")
})
public class RecommendationInteraction {

    @Id
    private String id;

    @Indexed
    private String userId;

    @Indexed
    private String contentId;

    /** SHOWN, OPENED, STARTED, COMPLETED, DISMISSED, ALREADY_COMPLETED, HELPFUL, NOT_USEFUL */
    private String interactionType;

    /** Client-generated idempotency key */
    private String requestId;

    private Instant createdAt;

    @Version
    private Long documentVersion;

    public RecommendationInteraction() {}

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getContentId() { return contentId; }
    public void setContentId(String contentId) { this.contentId = contentId; }

    public String getInteractionType() { return interactionType; }
    public void setInteractionType(String interactionType) { this.interactionType = interactionType; }

    public String getRequestId() { return requestId; }
    public void setRequestId(String requestId) { this.requestId = requestId; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }
}
